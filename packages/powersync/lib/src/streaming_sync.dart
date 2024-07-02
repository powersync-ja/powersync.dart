import 'dart:async';
import 'dart:convert' as convert;
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:powersync/src/abort_controller.dart';
import 'package:powersync/src/exceptions.dart';
import 'package:powersync/src/log_internal.dart';

import 'bucket_storage.dart';
import 'connector.dart';
import 'stream_utils.dart';
import 'sync_status.dart';
import 'sync_types.dart';

/// Since we use null to indicate "no change" in status updates, we need
/// a different value to indicate "no error".
const _noError = Object();

class StreamingSyncImplementation {
  BucketStorage adapter;

  final Future<PowerSyncCredentials?> Function() credentialsCallback;
  final Future<void> Function()? invalidCredentialsCallback;

  final Future<void> Function() uploadCrud;

  late http.Client _client;

  final Stream updateStream;

  final StreamController<SyncStatus> _statusStreamController =
      StreamController<SyncStatus>.broadcast();
  late final Stream<SyncStatus> statusStream;

  final StreamController<String?> _localPingController =
      StreamController.broadcast();

  final Duration retryDelay;

  SyncStatus lastStatus = const SyncStatus();

  AbortController? _abort;

  bool _safeToClose = true;

  StreamingSyncImplementation(
      {required this.adapter,
      required this.credentialsCallback,
      this.invalidCredentialsCallback,
      required this.uploadCrud,
      required this.updateStream,
      required this.retryDelay}) {
    _client = http.Client();
    statusStream = _statusStreamController.stream;
  }

  /// Close any active streams.
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
    // wait for completeAbort() to be called
    await future;

    // Now close the client in all cases not covered above
    _client.close();
  }

  bool get aborted {
    return _abort?.aborted ?? false;
  }

  Future<void> streamingSync() async {
    try {
      _abort = AbortController();
      crudLoop();
      var invalidCredentials = false;
      while (!aborted) {
        _updateStatus(connecting: true);
        try {
          if (invalidCredentials && invalidCredentialsCallback != null) {
            // This may error. In that case it will be retried again on the next
            // iteration.
            await invalidCredentialsCallback!();
            invalidCredentials = false;
          }
          await streamingSyncIteration();
          // Continue immediately
        } catch (e, stacktrace) {
          if (aborted && e is http.ClientException) {
            // Explicit abort requested - ignore. Example error:
            // ClientException: Connection closed while receiving data, uri=http://localhost:8080/sync/stream
            return;
          }
          final message = _syncErrorMessage(e);
          isolateLogger.warning('Sync error: $message', e, stacktrace);
          invalidCredentials = true;

          _updateStatus(
              connected: false,
              connecting: true,
              downloading: false,
              downloadError: e);

          // On error, wait a little before retrying
          // When aborting, don't wait
          await Future.any([Future.delayed(retryDelay), _abort!.onAbort]);
        }
      }
    } finally {
      _abort!.completeAbort();
    }
  }

  Future<void> crudLoop() async {
    await uploadAllCrud();

    await for (var _ in updateStream) {
      await uploadAllCrud();
    }
  }

  Future<void> uploadAllCrud() async {
    while (true) {
      try {
        bool done = await uploadCrudBatch();
        _updateStatus(uploadError: _noError);
        if (done) {
          break;
        }
      } catch (e, stacktrace) {
        isolateLogger.warning('Data upload error', e, stacktrace);
        _updateStatus(uploading: false, uploadError: e);
        await Future.delayed(retryDelay);
      }
    }
    _updateStatus(uploading: false);
  }

  Future<bool> uploadCrudBatch() async {
    if (adapter.hasCrud()) {
      _updateStatus(uploading: true);
      await uploadCrud();
      return false;
    } else {
      // This isolate is the only one triggering
      final updated = await adapter.updateLocalTarget(() async {
        return getWriteCheckpoint();
      });
      if (updated) {
        _localPingController.add(null);
      }

      return true;
    }
  }

  Future<String> getWriteCheckpoint() async {
    final credentials = await credentialsCallback();
    if (credentials == null) {
      throw CredentialsException("Not logged in");
    }
    final uri = credentials.endpointUri('write-checkpoint2.json');

    final response = await _client.get(uri, headers: {
      'Content-Type': 'application/json',
      'User-Id': credentials.userId ?? '',
      'Authorization': "Token ${credentials.token}"
    });
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

  /// Update sync status based on any non-null parameters.
  /// To clear errors, use [_noError] instead of null.
  void _updateStatus(
      {DateTime? lastSyncedAt,
      bool? hasSynced,
      bool? connected,
      bool? connecting,
      bool? downloading,
      bool? uploading,
      Object? uploadError,
      Object? downloadError}) {
    final c = connected ?? lastStatus.connected;
    var newStatus = SyncStatus(
        connected: c,
        connecting: !c && (connecting ?? lastStatus.connecting),
        lastSyncedAt: lastSyncedAt ?? lastStatus.lastSyncedAt,
        hasSynced: hasSynced ?? lastStatus.hasSynced,
        downloading: downloading ?? lastStatus.downloading,
        uploading: uploading ?? lastStatus.uploading,
        uploadError: uploadError == _noError
            ? null
            : (uploadError ?? lastStatus.uploadError),
        downloadError: downloadError == _noError
            ? null
            : (downloadError ?? lastStatus.downloadError));
    lastStatus = newStatus;
    _statusStreamController.add(newStatus);
  }

  Future<bool> streamingSyncIteration() async {
    adapter.startSession();
    final bucketEntries = adapter.getBucketStates();

    Map<String, String> initialBucketStates = {};

    for (final entry in bucketEntries) {
      initialBucketStates[entry.bucket] = entry.opId;
    }

    final List<BucketRequest> req = [];
    for (var entry in initialBucketStates.entries) {
      req.add(BucketRequest(entry.key, entry.value));
    }

    Checkpoint? targetCheckpoint;
    Checkpoint? validatedCheckpoint;
    Checkpoint? appliedCheckpoint;
    var bucketSet = Set<String>.from(initialBucketStates.keys);

    var requestStream = streamingSyncRequest(StreamingSyncRequest(req));

    var merged = addBroadcast(requestStream, _localPingController.stream);

    Future<void>? credentialsInvalidation;
    bool haveInvalidated = false;

    await for (var line in merged) {
      if (aborted) {
        break;
      }

      _updateStatus(connected: true, connecting: false);
      if (line is Checkpoint) {
        targetCheckpoint = line;
        final Set<String> bucketsToDelete = {...bucketSet};
        final Set<String> newBuckets = {};
        for (final checksum in line.checksums) {
          newBuckets.add(checksum.bucket);
          bucketsToDelete.remove(checksum.bucket);
        }
        bucketSet = newBuckets;
        await adapter.removeBuckets([...bucketsToDelete]);
        _updateStatus(downloading: true);
      } else if (line is StreamingSyncCheckpointComplete) {
        final result = await adapter.syncLocalDatabase(targetCheckpoint!);
        if (!result.checkpointValid) {
          // This means checksums failed. Start again with a new checkpoint.
          // TODO: better back-off
          // await new Promise((resolve) => setTimeout(resolve, 50));
          return false;
        } else if (!result.ready) {
          // Checksums valid, but need more data for a consistent checkpoint.
          // Continue waiting.
        } else {
          appliedCheckpoint = targetCheckpoint;

          _updateStatus(
              downloading: false,
              downloadError: _noError,
              lastSyncedAt: DateTime.now());
        }

        validatedCheckpoint = targetCheckpoint;
      } else if (line is StreamingSyncCheckpointDiff) {
        // TODO: It may be faster to just keep track of the diff, instead of the entire checkpoint
        if (targetCheckpoint == null) {
          throw PowerSyncProtocolException(
              'Checkpoint diff without previous checkpoint');
        }
        _updateStatus(downloading: true);
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

        bucketSet = Set.from(newBuckets.keys);
        await adapter.removeBuckets(diff.removedBuckets);
        adapter.setTargetCheckpoint(targetCheckpoint);
      } else if (line is SyncBucketData) {
        _updateStatus(downloading: true);
        await adapter.saveSyncData(SyncDataBatch([line]));
      } else if (line is StreamingSyncKeepalive) {
        if (line.tokenExpiresIn == 0) {
          // Token expired already - stop the connection immediately
          invalidCredentialsCallback?.call().ignore();
          break;
        } else if (line.tokenExpiresIn <= 30) {
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
      } else {
        if (targetCheckpoint == appliedCheckpoint) {
          _updateStatus(
              downloading: false,
              downloadError: _noError,
              lastSyncedAt: DateTime.now());
        } else if (validatedCheckpoint == targetCheckpoint) {
          final result = await adapter.syncLocalDatabase(targetCheckpoint!);
          if (!result.checkpointValid) {
            // This means checksums failed. Start again with a new checkpoint.
            // TODO: better back-off
            // await new Promise((resolve) => setTimeout(resolve, 50));
            return false;
          } else if (!result.ready) {
            // Checksums valid, but need more data for a consistent checkpoint.
            // Continue waiting.
          } else {
            appliedCheckpoint = targetCheckpoint;

            _updateStatus(
                downloading: false,
                downloadError: _noError,
                lastSyncedAt: DateTime.now());
          }
        }
      }

      if (haveInvalidated) {
        // Stop this connection, so that a new one will be started
        break;
      }
    }
    return true;
  }

  Stream<Object?> streamingSyncRequest(StreamingSyncRequest data) async* {
    final credentials = await credentialsCallback();
    if (credentials == null) {
      throw CredentialsException('Not logged in');
    }
    final uri = credentials.endpointUri('sync/stream');

    final request = http.Request('POST', uri);
    request.headers['Content-Type'] = 'application/json';
    request.headers['User-Id'] = credentials.userId ?? '';
    request.headers['Authorization'] = "Token ${credentials.token}";
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
    await for (var line in ndjson(res.stream)) {
      if (aborted) {
        break;
      }
      yield parseStreamingSyncLine(line as Map<String, dynamic>);
    }
  }
}

/// Attempt to give a basic summary of the error for cases where the full error
/// is not logged.
String _syncErrorMessage(Object? error) {
  if (error == null) {
    return 'Unknown';
  } else if (error is HttpException) {
    return 'Sync service error';
  } else if (error is SyncResponseException) {
    if (error.statusCode == 401) {
      return 'Authorization error';
    } else {
      return 'Sync service error';
    }
  } else if (error is SocketException) {
    return 'Connection error';
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
