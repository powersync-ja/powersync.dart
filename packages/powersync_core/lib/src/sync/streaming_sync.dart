import 'dart:async';
import 'dart:convert' as convert;

import 'package:http/http.dart' as http;
import 'package:meta/meta.dart';
import 'package:powersync_core/src/abort_controller.dart';
import 'package:powersync_core/src/exceptions.dart';
import 'package:powersync_core/src/log_internal.dart';
import 'package:powersync_core/src/user_agent/user_agent.dart';
import 'package:sqlite_async/mutex.dart';

import 'bucket_storage.dart';
import '../connector.dart';
import '../crud.dart';
import 'mutable_sync_status.dart';
import 'stream_utils.dart';
import 'sync_status.dart';
import 'protocol.dart';

abstract interface class StreamingSync {
  Stream<SyncStatus> get statusStream;

  Future<void> streamingSync();

  /// Close any active streams.
  Future<void> abort();
}

@internal
class StreamingSyncImplementation implements StreamingSync {
  final BucketStorage adapter;

  final Future<PowerSyncCredentials?> Function() credentialsCallback;
  final Future<void> Function()? invalidCredentialsCallback;
  final Future<void> Function() uploadCrud;
  final Stream<void> crudUpdateTriggerStream;

  // An internal controller which is used to trigger CRUD uploads internally
  // e.g. when reconnecting.
  // This is only a broadcast controller since the `crudLoop` method is public
  // and could potentially be called multiple times externally.
  final StreamController<Null> _internalCrudTriggerController =
      StreamController<Null>.broadcast();

  final http.Client _client;
  final SyncStatusStateStream _state = SyncStatusStateStream();

  final StreamController<Null> _localPingController =
      StreamController.broadcast();

  final Duration retryDelay;

  final Map<String, dynamic>? syncParameters;

  AbortController? _abort;

  bool _safeToClose = true;

  final Mutex syncMutex, crudMutex;
  Completer<void>? _activeCrudUpload;

  final Map<String, String> _userAgentHeaders;
  String? clientId;

  StreamingSyncImplementation({
    required this.adapter,
    required this.credentialsCallback,
    this.invalidCredentialsCallback,
    required this.uploadCrud,
    required this.crudUpdateTriggerStream,
    required this.retryDelay,
    this.syncParameters,
    required http.Client client,
    Mutex? syncMutex,
    Mutex? crudMutex,

    /// A unique identifier for this streaming sync implementation
    /// A good value is typically the DB file path which it will mutate when syncing.
    String? identifier = "unknown",
  })  : _client = client,
        syncMutex = syncMutex ?? Mutex(identifier: "sync-$identifier"),
        crudMutex = crudMutex ?? Mutex(identifier: "crud-$identifier"),
        _userAgentHeaders = userAgentHeaders();

  @override
  Stream<SyncStatus> get statusStream => _state.statusStream;

  @override
  Future<void> abort() async {
    // If streamingSync() hasn't been called yet, _abort will be null.
    var future = _abort?.abort();
    // This immediately triggers a new iteration in the merged stream, allowing us
    // to break immediately.
    // However, we still need to close the underlying stream explicitly, otherwise
    // the break will wait for the next line of data received on the stream.
    _localPingController.add(null);
    // According to the documentation, the behavior is undefined when calling
    // close() while requests are pending. However, this is no other
    // known way to cancel open streams, and this appears to end the stream with
    // a consistent ClientException if a request is open.
    // We avoid closing the client while opening a request, as that does cause
    // unpredicable uncaught errors.
    if (_safeToClose) {
      _client.close();
    }

    await _internalCrudTriggerController.close();

    // wait for completeAbort() to be called
    await future;

    // Now close the client in all cases not covered above
    _client.close();
    _state.close();
  }

  bool get aborted {
    return _abort?.aborted ?? false;
  }

  @override
  Future<void> streamingSync() async {
    try {
      _abort = AbortController();
      clientId = await adapter.getClientId();
      _crudLoop();
      var invalidCredentials = false;
      while (!aborted) {
        _state.updateStatus((s) => s.setConnectingIfNotConnected());
        try {
          if (invalidCredentials && invalidCredentialsCallback != null) {
            // This may error. In that case it will be retried again on the next
            // iteration.
            await invalidCredentialsCallback!();
            invalidCredentials = false;
          }
          // Protect sync iterations with exclusivity (if a valid Mutex is provided)
          await syncMutex.lock(() => streamingSyncIteration(),
              timeout: retryDelay);
        } catch (e, stacktrace) {
          if (aborted && e is http.ClientException) {
            // Explicit abort requested - ignore. Example error:
            // ClientException: Connection closed while receiving data, uri=http://localhost:8080/sync/stream
            return;
          }
          final message = _syncErrorMessage(e);
          isolateLogger.warning('Sync error: $message', e, stacktrace);
          invalidCredentials = true;

          _state.updateStatus((s) => s.applyDownloadError(e));

          // On error, wait a little before retrying
          // When aborting, don't wait
          await _delayRetry();
        }
      }
    } finally {
      _abort!.completeAbort();
    }
  }

  Future<void> _crudLoop() async {
    await _uploadAllCrud();

    // Trigger a CRUD upload whenever the upstream trigger fires
    // as-well-as whenever the sync stream reconnects.
    // This has the potential (in rare cases) to affect the crudThrottleTime,
    // but it should not result in excessive uploads since the
    // sync reconnects are also throttled.
    // The stream here is closed on abort.
    await for (var _ in mergeStreams(
        [crudUpdateTriggerStream, _internalCrudTriggerController.stream])) {
      await _uploadAllCrud();
    }
  }

  Future<void> _uploadAllCrud() {
    assert(_activeCrudUpload == null);
    final completer = _activeCrudUpload = Completer();
    return crudMutex.lock(() async {
      // Keep track of the first item in the CRUD queue for the last `uploadCrud` iteration.
      CrudEntry? checkedCrudItem;

      while (true) {
        try {
          // It's possible that an abort or disconnect operation could
          // be followed by a `close` operation. The close would cause these
          // operations, which use the DB, to throw an exception. Breaking the loop
          // here prevents unnecessary potential (caught) exceptions.
          if (aborted) {
            break;
          }
          // This is the first item in the FIFO CRUD queue.
          CrudEntry? nextCrudItem = await adapter.nextCrudItem();
          if (nextCrudItem != null) {
            _state.updateStatus((s) => s.uploading = true);
            if (nextCrudItem.clientId == checkedCrudItem?.clientId) {
              // This will force a higher log level than exceptions which are caught here.
              isolateLogger.warning(
                  """Potentially previously uploaded CRUD entries are still present in the upload queue. 
                Make sure to handle uploads and complete CRUD transactions or batches by calling and awaiting their [.complete()] method.
                The next upload iteration will be delayed.""");
              throw Exception(
                  'Delaying due to previously encountered CRUD item.');
            }

            checkedCrudItem = nextCrudItem;
            await uploadCrud();
            _state.updateStatus((s) => s.uploadError = null);
          } else {
            // Uploading is completed
            await adapter.updateLocalTarget(() => getWriteCheckpoint());
            break;
          }
        } catch (e, stacktrace) {
          checkedCrudItem = null;
          isolateLogger.warning('Data upload error', e, stacktrace);
          _state.updateStatus((s) => s.applyUploadError(e));
          await _delayRetry();

          if (!_state.status.connected) {
            // Exit the upload loop if the sync stream is no longer connected
            break;
          }
          isolateLogger.warning(
              "Caught exception when uploading. Upload will retry after a delay",
              e,
              stacktrace);
        } finally {
          _state.updateStatus((s) => s.uploading = false);
        }
      }
    }, timeout: retryDelay).whenComplete(() {
      assert(identical(_activeCrudUpload, completer));
      _activeCrudUpload = null;
      completer.complete();
    });
  }

  Future<String> getWriteCheckpoint() async {
    final credentials = await credentialsCallback();
    if (credentials == null) {
      throw CredentialsException("Not logged in");
    }
    final uri =
        credentials.endpointUri('write-checkpoint2.json?client_id=$clientId');

    Map<String, String> headers = {
      'Content-Type': 'application/json',
      'Authorization': "Token ${credentials.token}",
      ..._userAgentHeaders
    };

    final response = await _client.get(uri, headers: headers);
    if (response.statusCode == 401) {
      if (invalidCredentialsCallback != null) {
        await invalidCredentialsCallback!();
      }
    }
    if (response.statusCode != 200) {
      throw SyncResponseException.fromResponse(response);
    }

    final body = convert.jsonDecode(response.body);
    return body['data']['write_checkpoint'] as String;
  }

  void _updateStatusForPriority(SyncPriorityStatus completed) {
    _state.updateStatus((s) {
      // All status entries with a higher priority can be deleted since this
      // partial sync includes them.
      s.priorityStatusEntries = [
        for (final entry in s.priorityStatusEntries)
          if (entry.priority < completed.priority) entry,
        completed
      ];
    });
  }

  Future<(List<BucketRequest>, Map<String, BucketDescription?>)>
      _collectLocalBucketState() async {
    final bucketEntries = await adapter.getBucketStates();

    final initialRequests = [
      for (final entry in bucketEntries) BucketRequest(entry.bucket, entry.opId)
    ];
    final localDescriptions = {
      for (final entry in bucketEntries) entry.bucket: null
    };

    return (initialRequests, localDescriptions);
  }

  Future<void> streamingSyncIteration() async {
    var (bucketRequests, bucketMap) = await _collectLocalBucketState();
    if (aborted) {
      return;
    }

    Checkpoint? targetCheckpoint;
    Checkpoint? validatedCheckpoint;
    Checkpoint? appliedCheckpoint;

    var requestStream = streamingSyncRequest(
        StreamingSyncRequest(bucketRequests, syncParameters, clientId!));

    var merged = addBroadcast(requestStream, _localPingController.stream);

    Future<void>? credentialsInvalidation;
    bool haveInvalidated = false;

    // Trigger a CRUD upload on reconnect
    _internalCrudTriggerController.add(null);

    await for (var line in merged) {
      if (aborted) {
        break;
      }

      _state.updateStatus((s) => s.setConnected());
      switch (line) {
        case Checkpoint():
          targetCheckpoint = line;
          final Set<String> bucketsToDelete = {...bucketMap.keys};
          final Map<String, BucketDescription> newBuckets = {};
          for (final checksum in line.checksums) {
            newBuckets[checksum.bucket] = (
              name: checksum.bucket,
              priority: checksum.priority,
            );
            bucketsToDelete.remove(checksum.bucket);
          }
          bucketMap = newBuckets;
          await adapter.removeBuckets([...bucketsToDelete]);
          final initialProgress = await adapter.getBucketOperationProgress();
          _state.updateStatus(
              (s) => s.applyCheckpointStarted(initialProgress, line));
        case StreamingSyncCheckpointComplete():
          final result = await _applyCheckpoint(targetCheckpoint!, _abort);
          if (result.abort) {
            return;
          }
          validatedCheckpoint = targetCheckpoint;
          if (result.didApply) {
            appliedCheckpoint = targetCheckpoint;
          }
        case StreamingSyncCheckpointPartiallyComplete(:final bucketPriority):
          final result = await adapter.syncLocalDatabase(targetCheckpoint!,
              forPriority: bucketPriority);
          if (!result.checkpointValid) {
            // This means checksums failed. Start again with a new checkpoint.
            // TODO: better back-off
            // await new Promise((resolve) => setTimeout(resolve, 50));
            return;
          } else if (!result.ready) {
            // If we have pending uploads, we can't complete new checkpoints
            // outside of priority 0. We'll resolve this for a complete
            // checkpoint later.
          } else {
            _updateStatusForPriority((
              priority: BucketPriority(bucketPriority),
              lastSyncedAt: DateTime.now(),
              hasSynced: true,
            ));
          }
        case StreamingSyncCheckpointDiff():
          // TODO: It may be faster to just keep track of the diff, instead of
          // the entire checkpoint
          if (targetCheckpoint == null) {
            throw PowerSyncProtocolException(
                'Checkpoint diff without previous checkpoint');
          }
          final diff = line;
          final Map<String, BucketChecksum> newBuckets = {};
          for (var checksum in targetCheckpoint.checksums) {
            newBuckets[checksum.bucket] = checksum;
          }
          for (var checksum in diff.updatedBuckets) {
            newBuckets[checksum.bucket] = checksum;
          }
          for (var bucket in diff.removedBuckets) {
            newBuckets.remove(bucket);
          }

          final newCheckpoint = Checkpoint(
              lastOpId: diff.lastOpId,
              checksums: [...newBuckets.values],
              writeCheckpoint: diff.writeCheckpoint);
          targetCheckpoint = newCheckpoint;
          final initialProgress = await adapter.getBucketOperationProgress();
          _state.updateStatus(
              (s) => s.applyCheckpointStarted(initialProgress, newCheckpoint));

          bucketMap = newBuckets.map((name, checksum) =>
              MapEntry(name, (name: name, priority: checksum.priority)));
          await adapter.removeBuckets(diff.removedBuckets);
          adapter.setTargetCheckpoint(targetCheckpoint);
        case SyncDataBatch():
          // TODO: This increments the counters before actually saving sync
          // data. Might be fine though?
          _state.updateStatus((s) => s.applyBatchReceived(line));
          await adapter.saveSyncData(line);
        case StreamingSyncKeepalive(:final tokenExpiresIn):
          if (tokenExpiresIn == 0) {
            // Token expired already - stop the connection immediately
            invalidCredentialsCallback?.call().ignore();
            break;
          } else if (tokenExpiresIn <= 30) {
            // Token expires soon - refresh it in the background
            if (credentialsInvalidation == null &&
                invalidCredentialsCallback != null) {
              credentialsInvalidation = invalidCredentialsCallback!().then((_) {
                // Token has been refreshed - we should restart the connection.
                haveInvalidated = true;
                // trigger next loop iteration ASAP, don't wait for another
                // message from the server.
                _localPingController.add(null);
              }, onError: (_) {
                // Token refresh failed - retry on next keepalive.
                credentialsInvalidation = null;
              });
            }
          }
        case UnknownSyncLine(:final rawData):
          isolateLogger.fine('Unknown sync line: $rawData');
        case null: // Local ping
          if (targetCheckpoint == appliedCheckpoint) {
            if (appliedCheckpoint case final completed?) {
              _state.updateStatus((s) => s.applyCheckpointReached(completed));
            }
          } else if (validatedCheckpoint == targetCheckpoint) {
            final result = await _applyCheckpoint(targetCheckpoint!, _abort);
            if (result.abort) {
              return;
            }
            if (result.didApply) {
              appliedCheckpoint = targetCheckpoint;
            }
          }
      }

      if (haveInvalidated) {
        // Stop this connection, so that a new one will be started
        break;
      }
    }
  }

  Future<({bool abort, bool didApply})> _applyCheckpoint(
      Checkpoint targetCheckpoint, AbortController? abortController) async {
    var result = await adapter.syncLocalDatabase(targetCheckpoint);
    final pendingUpload = _activeCrudUpload;

    if (!result.checkpointValid) {
      // This means checksums failed. Start again with a new checkpoint.
      // TODO: better back-off
      // await new Promise((resolve) => setTimeout(resolve, 50));
      return const (abort: true, didApply: false);
    } else if (!result.ready && pendingUpload != null) {
      // We have pending entries in the local upload queue or are waiting to
      // confirm a write checkpoint, which prevented this checkpoint from
      // applying. Wait for that to complete and try again.
      isolateLogger.fine('Could not apply checkpoint due to local data. '
          'Waiting for in-progress upload before retrying...');
      await Future.any([
        pendingUpload.future,
        if (abortController case final controller?) controller.onAbort,
      ]);

      if (abortController?.aborted == true) {
        return const (abort: true, didApply: false);
      }

      // Try again now that uploads have completed.
      result = await adapter.syncLocalDatabase(targetCheckpoint);
    }

    if (result.checkpointValid && result.ready) {
      isolateLogger.fine('validated checkpoint: $targetCheckpoint');

      _state.updateStatus((s) => s.applyCheckpointReached(targetCheckpoint));

      return const (abort: false, didApply: true);
    } else {
      isolateLogger.fine(
          'Could not apply checkpoint. Waiting for next sync complete line');
      return const (abort: false, didApply: false);
    }
  }

  Stream<StreamingSyncLine> streamingSyncRequest(
      StreamingSyncRequest data) async* {
    final credentials = await credentialsCallback();
    if (credentials == null) {
      throw CredentialsException('Not logged in');
    }
    final uri = credentials.endpointUri('sync/stream');

    final request = http.Request('POST', uri);
    request.headers['Content-Type'] = 'application/json';
    request.headers['Authorization'] = "Token ${credentials.token}";
    request.headers.addAll(_userAgentHeaders);

    request.body = convert.jsonEncode(data);

    http.StreamedResponse res;
    try {
      // Do not close the client during the request phase - this causes uncaught errors.
      _safeToClose = false;
      res = await _client.send(request);
    } finally {
      _safeToClose = true;
    }
    if (aborted) {
      return;
    }

    if (res.statusCode == 401) {
      if (invalidCredentialsCallback != null) {
        await invalidCredentialsCallback!();
      }
    }
    if (res.statusCode != 200) {
      throw await SyncResponseException.fromStreamedResponse(res);
    }

    // Note: The response stream is automatically closed when this loop errors
    yield* ndjson(res.stream)
        .cast<Map<String, dynamic>>()
        .transform(StreamingSyncLine.reader)
        .takeWhile((_) => !aborted);
  }

  /// Delays the standard `retryDelay` Duration, but exits early if
  /// an abort has been requested.
  Future<void> _delayRetry() async {
    await Future.any([Future<void>.delayed(retryDelay), _abort!.onAbort]);
  }
}

/// Attempt to give a basic summary of the error for cases where the full error
/// is not logged.
String _syncErrorMessage(Object? error) {
  if (error == null) {
    return 'Unknown';
  } else if (error is http.ClientException) {
    return 'Sync service error';
  } else if (error is SyncResponseException) {
    if (error.statusCode == 401) {
      return 'Authorization error';
    } else {
      return 'Sync service error';
    }
  } else if (error is ArgumentError || error is FormatException) {
    return 'Configuration error';
  } else if (error is CredentialsException) {
    return 'Credentials error';
  } else if (error is PowerSyncProtocolException) {
    return 'Protocol error';
  } else {
    return '${error.runtimeType}';
  }
}

typedef BucketDescription = ({
  String name,
  int priority,
});
