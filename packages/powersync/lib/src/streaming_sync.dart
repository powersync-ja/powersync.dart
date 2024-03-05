import 'dart:async';
import 'dart:convert' as convert;
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

  final Stream updateStream;

  final StreamController<SyncStatus> _statusStreamController =
      StreamController<SyncStatus>.broadcast();
  late final Stream<SyncStatus> statusStream;

  late final http.Client _client;

  final StreamController _localPingController = StreamController.broadcast();

  final Duration retryDelay;

  SyncStatus lastStatus = const SyncStatus();

  StreamingSyncImplementation(
      {required this.adapter,
      required this.credentialsCallback,
      this.invalidCredentialsCallback,
      required this.uploadCrud,
      required this.updateStream,
      required this.retryDelay,
      required http.Client client}) {
    _client = client;
    statusStream = _statusStreamController.stream;
  }

  Future<void> streamingSync(AbortController? abortController) async {
    crudLoop();
    var invalidCredentials = false;
    while (true) {
      if (abortController?.aborted == true) {
        abortController!.completeAbort();
        return;
      }
      _updateStatus(connecting: true);
      try {
        if (invalidCredentials && invalidCredentialsCallback != null) {
          // This may error. In that case it will be retried again on the next
          // iteration.
          await invalidCredentialsCallback!();
          invalidCredentials = false;
        }
        await streamingSyncIteration(abortController);
        // Continue immediately
      } catch (e, stacktrace) {
        final message = _syncErrorMessage(e);
        isolateLogger.warning('Sync error: $message', e, stacktrace);
        invalidCredentials = true;

        _updateStatus(
            connected: false,
            connecting: true,
            downloading: false,
            downloadError: e);

        // On error, wait a little before retrying
        await Future.delayed(retryDelay);
      }
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
    if ((await adapter.hasCrud())) {
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

  Future<bool> streamingSyncIteration(AbortController? abortController) async {
    adapter.startSession();
    final bucketEntries = await adapter.getBucketStates();

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
      if (abortController?.aborted == true) {
        return false;
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
        adapter.setTargetCheckpoint(targetCheckpoint);
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
        _updateStatus(downloading: true);
      } else if (line is SyncBucketData) {
        await adapter.saveSyncData(SyncDataBatch([line]));
        _updateStatus(downloading: true);
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
    request.headers['Authorization'] = "Token ${credentials.token}";
    request.body = convert.jsonEncode(data);

    final res = await _client.send(request);

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
      yield parseStreamingSyncLine(line as Map<String, dynamic>);
    }
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
