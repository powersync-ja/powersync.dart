import 'dart:async';
import 'dart:convert' as convert;
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:logging/logging.dart';
import 'package:meta/meta.dart';
import 'package:powersync_core/src/abort_controller.dart';
import 'package:powersync_core/src/exceptions.dart';
import 'package:powersync_core/src/log_internal.dart';
import 'package:powersync_core/src/sync/options.dart';
import 'package:powersync_core/src/user_agent/user_agent.dart';
import 'package:sqlite_async/mutex.dart';

import '../crud.dart';
import 'bucket_storage.dart';
import 'instruction.dart';
import 'internal_connector.dart';
import 'mutable_sync_status.dart';
import 'protocol.dart';
import 'stream_utils.dart';
import 'sync_status.dart';

typedef SubscribedStream = ({String name, String parameters});

abstract interface class StreamingSync {
  Stream<SyncStatus> get statusStream;

  Future<void> streamingSync();

  /// Close any active streams.
  Future<void> abort();

  void updateSubscriptions(List<SubscribedStream> streams);
}

@internal
class StreamingSyncImplementation implements StreamingSync {
  final String schemaJson;
  final BucketStorage adapter;
  final InternalConnector connector;
  final ResolvedSyncOptions options;
  List<SubscribedStream> _activeSubscriptions;

  final Logger logger;

  final Stream<void> crudUpdateTriggerStream;

  // An internal controller which is used to trigger CRUD uploads internally
  // e.g. when reconnecting.
  // This is only a broadcast controller since the `crudLoop` method is public
  // and could potentially be called multiple times externally.
  final StreamController<Null> _internalCrudTriggerController =
      StreamController<Null>.broadcast();

  final http.Client _client;

  final SyncStatusStateStream _state = SyncStatusStateStream();

  AbortController? _abort;

  final Mutex syncMutex, crudMutex;
  Completer<void>? _activeCrudUpload;
  final StreamController<SyncEvent> _nonLineSyncEvents =
      StreamController.broadcast();

  final Map<String, String> _userAgentHeaders;
  String? clientId;

  StreamingSyncImplementation({
    required this.schemaJson,
    required this.adapter,
    required this.connector,
    required this.crudUpdateTriggerStream,
    required this.options,
    required http.Client client,
    List<SubscribedStream> activeSubscriptions = const [],
    Mutex? syncMutex,
    Mutex? crudMutex,
    Logger? logger,

    /// A unique identifier for this streaming sync implementation
    /// A good value is typically the DB file path which it will mutate when syncing.
    String? identifier = "unknown",
  })  : _client = client,
        syncMutex = syncMutex ?? Mutex(identifier: "sync-$identifier"),
        crudMutex = crudMutex ?? Mutex(identifier: "crud-$identifier"),
        _userAgentHeaders = userAgentHeaders(),
        logger = logger ?? isolateLogger,
        _activeSubscriptions = activeSubscriptions;

  Duration get _retryDelay => options.retryDelay;

  @override
  Stream<SyncStatus> get statusStream => _state.statusStream;

  @override
  Future<void> abort() async {
    // If streamingSync() hasn't been called yet, _abort will be null.
    if (_abort case final abort?) {
      final future = abort.abort();
      _internalCrudTriggerController.close();

      // If a sync iteration is active, the control flow to abort is:
      //
      //  1. We close the non-line sync event stream here.
      //  2. This emits a done event.
      //  3. `addBroadcastStream` will cancel all source subscriptions in
      //      response to that, and then emit a done event too. If there is an
      //      error while cancelling the stream, it's forwarded by emitting an
      //      error before closing.
      //  4. We break out of the sync loop (either due to an error or because
      //     all resources have been closed correctly).
      //  5. `streamingSync` completes the abort controller, which we await
      //     here.
      await _nonLineSyncEvents.close();

      // Wait for the abort to complete, which also guarantees that no requests
      // are pending.
      await Future.wait([
        future,
        if (_activeCrudUpload case final activeUpload?) activeUpload.future,
      ]);

      _client.close();
      _state.close();
    }
  }

  bool get aborted {
    return _abort?.aborted ?? false;
  }

  @override
  void updateSubscriptions(List<SubscribedStream> streams) {
    _activeSubscriptions = streams;
    if (_nonLineSyncEvents.hasListener) {
      _nonLineSyncEvents.add(HandleChangedSubscriptions(streams));
    }
  }

  @override
  Future<void> streamingSync() async {
    try {
      assert(_abort == null);
      _abort = AbortController();
      clientId = await adapter.getClientId();
      _crudLoop();
      var invalidCredentials = false;
      while (!aborted) {
        _state.updateStatus((s) => s.setConnectingIfNotConnected());
        try {
          if (invalidCredentials) {
            // This may error. In that case it will be retried again on the next
            // iteration.
            await connector.prefetchCredentials();
            invalidCredentials = false;
          }
          // Protect sync iterations with exclusivity (if a valid Mutex is provided)
          await syncMutex.lock(() {
            switch (options.source.syncImplementation) {
              // ignore: deprecated_member_use_from_same_package
              case SyncClientImplementation.dart:
                return _dartStreamingSyncIteration();
              case SyncClientImplementation.rust:
                return _rustStreamingSyncIteration();
            }
          }, timeout: _retryDelay);
        } catch (e, stacktrace) {
          if (aborted && e is http.ClientException) {
            // Explicit abort requested - ignore. Example error:
            // ClientException: Connection closed while receiving data, uri=http://localhost:8080/sync/stream
            return;
          }
          final message = _syncErrorMessage(e);
          logger.warning('Sync error: $message', e, stacktrace);
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
              logger.warning(
                  """Potentially previously uploaded CRUD entries are still present in the upload queue. 
                Make sure to handle uploads and complete CRUD transactions or batches by calling and awaiting their [.complete()] method.
                The next upload iteration will be delayed.""");
              throw Exception(
                  'Delaying due to previously encountered CRUD item.');
            }

            checkedCrudItem = nextCrudItem;
            await connector.uploadCrud();
            _state.updateStatus((s) => s.uploadError = null);
          } else {
            // Uploading is completed
            await adapter.updateLocalTarget(() => getWriteCheckpoint());
            break;
          }
        } catch (e, stacktrace) {
          checkedCrudItem = null;
          logger.warning('Data upload error', e, stacktrace);
          _state.updateStatus((s) => s.applyUploadError(e));
          await _delayRetry();

          if (!_state.status.connected) {
            // Exit the upload loop if the sync stream is no longer connected
            break;
          }
          logger.warning(
              "Caught exception when uploading. Upload will retry after a delay",
              e,
              stacktrace);
        } finally {
          _state.updateStatus((s) => s.uploading = false);
        }
      }
    }, timeout: _retryDelay).whenComplete(() {
      if (!aborted) {
        _nonLineSyncEvents.add(const UploadCompleted());
      }

      assert(identical(_activeCrudUpload, completer));
      _activeCrudUpload = null;
      completer.complete();
    });
  }

  Future<String> getWriteCheckpoint() async {
    final credentials = await connector.getCredentialsCached();
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
      await connector.prefetchCredentials();
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

  Future<void> _rustStreamingSyncIteration() async {
    logger.info('Starting Rust sync iteration');
    final response = await _ActiveRustStreamingIteration(this).syncIteration();
    logger.info(
        'Ending Rust sync iteration. Immediate restart: ${response.immediateRestart}');
    // Note: With the current loop in streamingSync(), any return value that
    // isn't an exception triggers an immediate restart.
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

  Future<void> _dartStreamingSyncIteration() async {
    var (bucketRequests, bucketMap) = await _collectLocalBucketState();
    if (aborted) {
      return;
    }

    Checkpoint? targetCheckpoint;

    var requestStream = _streamingSyncRequest(StreamingSyncRequest(
            bucketRequests, options.params, clientId!, options.appMetadata))
        .map(ReceivedLine.new);

    var merged = addBroadcast(requestStream, _nonLineSyncEvents.stream);

    Future<void>? credentialsInvalidation;
    bool shouldStopIteration = false;

    // Trigger a CRUD upload on reconnect
    _internalCrudTriggerController.add(null);

    Future<void> handleLine(StreamingSyncLine line) async {
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
            shouldStopIteration = true;
            return;
          }
        case StreamingSyncCheckpointPartiallyComplete(:final bucketPriority):
          final result = await adapter.syncLocalDatabase(targetCheckpoint!,
              forPriority: bucketPriority);
          if (!result.checkpointValid) {
            // This means checksums failed. Start again with a new checkpoint.
            // TODO: better back-off
            // await new Promise((resolve) => setTimeout(resolve, 50));
            shouldStopIteration = true;
            return;
          } else if (!result.ready) {
            // If we have pending uploads, we can't complete new checkpoints
            // outside of priority 0. We'll resolve this for a complete
            // checkpoint later.
          } else {
            _updateStatusForPriority((
              priority: StreamPriority(bucketPriority),
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
          for (var checksum in targetCheckpoint!.checksums) {
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
          adapter.setTargetCheckpoint(targetCheckpoint!);
        case SyncDataBatch():
          // TODO: This increments the counters before actually saving sync
          // data. Might be fine though?
          _state.updateStatus((s) => s.applyBatchReceived(line));
          await adapter.saveSyncData(line);
        case StreamingSyncKeepalive(:final tokenExpiresIn):
          if (tokenExpiresIn == 0) {
            // Token expired already - stop the connection immediately
            connector.prefetchCredentials(invalidate: true).ignore();
            shouldStopIteration = true;
            break;
          } else if (tokenExpiresIn <= 30) {
            // Token expires soon - refresh it in the background
            credentialsInvalidation ??=
                connector.prefetchCredentials().then((_) {
              // Token has been refreshed - we should restart the connection.
              shouldStopIteration = true;
              // trigger next loop iteration ASAP, don't wait for another
              // message from the server.
              if (!aborted) {
                _nonLineSyncEvents.add(TokenRefreshComplete());
              }
            }, onError: (_) {
              // Token refresh failed - retry on next keepalive.
              credentialsInvalidation = null;
            });
          }
        case UnknownSyncLine(:final rawData):
          logger.fine('Unknown sync line: $rawData');
      }
    }

    await for (var line in merged) {
      if (aborted || shouldStopIteration) {
        break;
      }

      switch (line) {
        case ReceivedLine(:final line):
          _state.updateStatus((s) => s.setConnected());
          await handleLine(line as StreamingSyncLine);
        case UploadCompleted():
        case HandleChangedSubscriptions():
        case ConnectionEvent():
          // Only relevant for the Rust sync implementation.
          break;
        case AbortCurrentIteration():
        case TokenRefreshComplete():
          // We have a new token, so stop the iteration.
          shouldStopIteration = true;
      }

      if (shouldStopIteration) {
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
      logger.fine('Could not apply checkpoint due to local data. '
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
      logger.fine('validated checkpoint: $targetCheckpoint');

      _state.updateStatus((s) => s.applyCheckpointReached(targetCheckpoint));

      return const (abort: false, didApply: true);
    } else {
      logger.fine(
          'Could not apply checkpoint. Waiting for next sync complete line');
      return const (abort: false, didApply: false);
    }
  }

  Future<http.StreamedResponse?> _postStreamRequest(
      Object? data, bool acceptBson,
      {Future<void>? onAbort}) async {
    const ndJson = 'application/x-ndjson';
    const bson = 'application/vnd.powersync.bson-stream';

    final credentials = await connector.getCredentialsCached();
    if (credentials == null) {
      throw CredentialsException('Not logged in');
    }
    final uri = credentials.endpointUri('sync/stream');

    final request = http.AbortableRequest('POST', uri,
        abortTrigger: onAbort ?? _abort!.onAbort);
    request.headers['Content-Type'] = 'application/json';
    request.headers['Authorization'] = "Token ${credentials.token}";
    request.headers['Accept'] =
        acceptBson ? '$bson;q=0.9,$ndJson;q=0.8' : ndJson;
    request.headers.addAll(_userAgentHeaders);

    request.body = convert.jsonEncode(data);

    final res = await _client.send(request);
    if (aborted) {
      return null;
    }

    if (res.statusCode == 401) {
      await connector.prefetchCredentials(invalidate: true);
    }
    if (res.statusCode != 200) {
      throw await SyncResponseException.fromStreamedResponse(res);
    }

    return res;
  }

  Stream<StreamingSyncLine> _streamingSyncRequest(StreamingSyncRequest data) {
    return streamFromFutureAwaitInCancellation(_postStreamRequest(data, false))
        .asyncExpand((response) {
      return response?.stream.lines.parseJson
          .cast<Map<String, dynamic>>()
          .transform(StreamingSyncLine.reader);
    });
  }

  /// Delays the standard `retryDelay` Duration, but exits early if
  /// an abort has been requested.
  Future<void> _delayRetry() async {
    await Future.any([Future<void>.delayed(_retryDelay), _abort!.onAbort]);
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
    return '${error.runtimeType}: $error';
  }
}

typedef BucketDescription = ({
  String name,
  int priority,
});

final class _ActiveRustStreamingIteration {
  final StreamingSyncImplementation sync;

  var _isActive = true;
  var _hadSyncLine = false;

  StreamSubscription<void>? _completedUploads;
  final Completer<RustSyncIterationResult> _completedStream = Completer();

  _ActiveRustStreamingIteration(this.sync);

  List<Object?> _encodeSubscriptions(List<SubscribedStream> subscriptions) {
    return sync._activeSubscriptions
        .map((s) =>
            {'name': s.name, 'params': convert.json.decode(s.parameters)})
        .toList();
  }

  Future<RustSyncIterationResult> syncIteration() async {
    try {
      await _control(
        'start',
        convert.json.encode({
          'app_metadata': sync.options.appMetadata,
          'parameters': sync.options.params,
          'schema': convert.json.decode(sync.schemaJson),
          'include_defaults': sync.options.includeDefaultStreams,
          'active_streams': _encodeSubscriptions(sync._activeSubscriptions),
        }),
      );
      assert(_completedStream.isCompleted, 'Should have started streaming');
      return await _completedStream.future;
    } finally {
      _isActive = false;
      _completedUploads?.cancel();
      await _stop();
    }
  }

  Stream<SyncEvent> _receiveLines(Object? data,
      {required Future<void> onAbort}) {
    return streamFromFutureAwaitInCancellation(
            sync._postStreamRequest(data, true, onAbort: onAbort))
        .asyncExpand<SyncEvent>((response) async* {
      if (response == null) {
        return;
      } else {
        yield ConnectionEvent.established;

        final contentType = response.headers['content-type'];
        final isBson = contentType == 'application/vnd.powersync.bson-stream';

        yield* (isBson ? response.stream.bsonDocuments : response.stream.lines)
            .map(ReceivedLine.new);
        yield ConnectionEvent.end;
      }
    });
  }

  Future<RustSyncIterationResult> _handleLines(
      EstablishSyncStream request) async {
    // This is a workaround for https://github.com/dart-lang/http/issues/1820:
    // When cancelling the stream subscription of an HTTP response with the
    // fetch-based client implementation, cancelling the subscription is delayed
    // until the next chunk (typically a token_expires_in message in our case).
    // So, before cancelling, we complete an abort controller for the request to
    // speed things up. This is not an issue in most cases because the abort
    // controller on this stream would be completed when disconnecting. But
    // when switching sync streams, that's not the case and we need a second
    // abort controller for the inner iteration.
    final innerAbort = Completer<void>.sync();
    final events = addBroadcast(
      _receiveLines(
        request.request,
        onAbort: Future.any([
          sync._abort!.onAbort,
          innerAbort.future,
        ]),
      ),
      sync._nonLineSyncEvents.stream,
    );

    var needsImmediateRestart = false;
    loop:
    try {
      await for (final event in events) {
        if (!_isActive || sync.aborted) {
          innerAbort.complete();
          break;
        }

        switch (event) {
          case ConnectionEvent():
            await _control('connection', event.name);
          case ReceivedLine(line: final Uint8List line):
            _triggerCrudUploadOnFirstLine();
            await _control('line_binary', line);
          case ReceivedLine(line: final line as String):
            _triggerCrudUploadOnFirstLine();
            await _control('line_text', line);
          case UploadCompleted():
            await _control('completed_upload');
          case AbortCurrentIteration(:final hideDisconnectState):
            innerAbort.complete();
            needsImmediateRestart = hideDisconnectState;
            break loop;
          case TokenRefreshComplete():
            await _control('refreshed_token');
          case HandleChangedSubscriptions(:final currentSubscriptions):
            await _control(
                'update_subscriptions',
                convert.json
                    .encode(_encodeSubscriptions(currentSubscriptions)));
        }
      }
    } on http.RequestAbortedException {
      // Unlike a regular cancellation, cancelling via the abort controller
      // emits an error. We did mean to just cancel the stream, so we can
      // safely ignore that.
      if (innerAbort.isCompleted) {
        // ignore
      } else {
        rethrow;
      }
    }

    return (immediateRestart: needsImmediateRestart);
  }

  /// Triggers a local CRUD upload when the first sync line has been received.
  ///
  /// This allows uploading local changes that have been made while offline or
  /// disconnected.
  void _triggerCrudUploadOnFirstLine() {
    if (!_hadSyncLine) {
      sync._internalCrudTriggerController.add(null);
      _hadSyncLine = true;
    }
  }

  Future<void> _stop() {
    return _control('stop');
  }

  Future<void> _control(String operation, [Object? payload]) async {
    final rawResponse = await sync.adapter.control(operation, payload);
    final instructions = convert.json.decode(rawResponse) as List;

    for (final instruction in instructions) {
      await _handleInstruction(
          Instruction.fromJson(instruction as Map<String, Object?>));
    }
  }

  Future<void> _handleInstruction(Instruction instruction) async {
    switch (instruction) {
      case LogLine(:final severity, :final line):
        sync.logger.log(
            switch (severity) {
              'DEBUG' => Level.FINE,
              'INFO' => Level.INFO,
              _ => Level.WARNING,
            },
            line);
      case EstablishSyncStream():
        _completedStream.complete(_handleLines(instruction));
      case UpdateSyncStatus(:final status):
        sync._state.updateStatus((m) => m.applyFromCore(status));
      case FetchCredentials(:final didExpire):
        if (didExpire) {
          await sync.connector.prefetchCredentials(invalidate: true);
        } else {
          sync.connector.prefetchCredentials().then((_) {
            if (_isActive && !sync.aborted) {
              sync._nonLineSyncEvents.add(const TokenRefreshComplete());
            }
          }, onError: (Object e, StackTrace s) {
            sync.logger.warning('Could not prefetch credentials', e, s);
          });
        }
      case CloseSyncStream(:final hideDisconnect):
        if (!sync.aborted) {
          _isActive = false;
          sync._nonLineSyncEvents
              .add(AbortCurrentIteration(hideDisconnectState: hideDisconnect));
        }
      case FlushFileSystem():
        await sync.adapter.flushFileSystem();
      case DidCompleteSync():
        sync._state.updateStatus((m) => m.downloadError = null);
      case UnknownSyncInstruction(:final source):
        sync.logger.warning('Unknown instruction: $source');
    }
  }
}

typedef RustSyncIterationResult = ({bool immediateRestart});

sealed class SyncEvent {}

enum ConnectionEvent implements SyncEvent {
  established,
  end,
}

final class ReceivedLine implements SyncEvent {
  final Object /* String|Uint8List|StreamingSyncLine */ line;

  const ReceivedLine(this.line);
}

final class UploadCompleted implements SyncEvent {
  const UploadCompleted();
}

final class TokenRefreshComplete implements SyncEvent {
  const TokenRefreshComplete();
}

final class AbortCurrentIteration implements SyncEvent {
  /// Whether we should immediately disconnect and hide the `disconnected`
  /// state.
  ///
  /// This is used when we're changing subscription, to hide the brief downtime
  /// we have while reconnecting.
  final bool hideDisconnectState;

  const AbortCurrentIteration({this.hideDisconnectState = false});
}

final class HandleChangedSubscriptions implements SyncEvent {
  final List<SubscribedStream> currentSubscriptions;

  HandleChangedSubscriptions(this.currentSubscriptions);
}
