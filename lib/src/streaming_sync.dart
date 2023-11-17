import 'dart:async';
import 'dart:convert' as convert;
import 'dart:io';

import 'package:http/http.dart' as http;

import 'bucket_storage.dart';
import 'connector.dart';
import 'log.dart';
import 'stream_utils.dart';
import 'sync_status.dart';
import 'sync_types.dart';

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

  final StreamController _localPingController = StreamController.broadcast();

  final Duration retryDelay;

  DateTime? lastSyncedAt;

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

  Future<void> streamingSync() async {
    crudLoop();
    var invalidCredentials = false;
    while (true) {
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
        log.warning('Sync error', e, stacktrace);
        invalidCredentials = true;

        _statusStreamController
            .add(SyncStatus(connected: false, lastSyncedAt: lastSyncedAt));

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
        if (done) {
          break;
        }
      } catch (e, stacktrace) {
        log.warning('Data upload error', e, stacktrace);
        await Future.delayed(retryDelay);
      }
    }
  }

  Future<bool> uploadCrudBatch() async {
    if (adapter.hasCrud()) {
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
      throw AssertionError("Not logged in");
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
      throw getError(response);
    }

    final body = convert.jsonDecode(response.body);
    return body['data']['write_checkpoint'] as String;
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
      _statusStreamController
          .add(SyncStatus(connected: true, lastSyncedAt: lastSyncedAt));
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
          lastSyncedAt = DateTime.now();
          _statusStreamController
              .add(SyncStatus(connected: true, lastSyncedAt: lastSyncedAt));
        }

        validatedCheckpoint = targetCheckpoint;
      } else if (line is StreamingSyncCheckpointDiff) {
        // TODO: It may be faster to just keep track of the diff, instead of the entire checkpoint
        if (targetCheckpoint == null) {
          throw AssertionError('Checkpoint diff without previous checkpoint');
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
      } else if (line is SyncBucketData) {
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
          lastSyncedAt = DateTime.now();
          _statusStreamController
              .add(SyncStatus(connected: true, lastSyncedAt: lastSyncedAt));
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
            lastSyncedAt = DateTime.now();
            _statusStreamController
                .add(SyncStatus(connected: true, lastSyncedAt: lastSyncedAt));
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
      throw AssertionError('Not logged in');
    }
    final uri = credentials.endpointUri('sync/stream');

    final request = http.Request('POST', uri);
    request.headers['Content-Type'] = 'application/json';
    request.headers['User-Id'] = credentials.userId ?? '';
    request.headers['Authorization'] = "Token ${credentials.token}";
    request.body = convert.jsonEncode(data);

    final res = await _client.send(request);
    if (res.statusCode == 401) {
      if (invalidCredentialsCallback != null) {
        await invalidCredentialsCallback!();
      }
    }
    if (res.statusCode != 200) {
      throw await getStreamedError(res);
    }

    // Note: The response stream is automatically closed when this loop errors
    await for (var line in ndjson(res.stream)) {
      yield parseStreamingSyncLine(line as Map<String, dynamic>);
    }
  }
}

HttpException getError(http.Response response) {
  try {
    final body = response.body;
    final decoded = convert.jsonDecode(body);
    final details = decoded['error']?['details']?[0] ?? body;
    final message = '${response.reasonPhrase ?? "Request failed"}: $details';
    return HttpException(message, uri: response.request?.url);
  } on Error catch (_) {
    return HttpException(response.reasonPhrase ?? "Request failed",
        uri: response.request?.url);
  }
}

Future<HttpException> getStreamedError(http.StreamedResponse response) async {
  try {
    final body = await response.stream.bytesToString();
    final decoded = convert.jsonDecode(body);
    final details = decoded['error']?['details']?[0] ?? body;
    final message = '${response.reasonPhrase ?? "Request failed"}: $details';
    return HttpException(message, uri: response.request?.url);
  } on Error catch (_) {
    return HttpException(response.reasonPhrase ?? "Request failed",
        uri: response.request?.url);
  }
}
