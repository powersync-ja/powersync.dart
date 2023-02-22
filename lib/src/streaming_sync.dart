import 'dart:async';
import 'dart:io';

import './bucket_storage.dart';
import 'package:http/http.dart' as http;
import 'package:http/http.dart';
import 'dart:convert' as convert;
import 'package:async/async.dart';
import './connector.dart';

class SyncStatus {
  /// true if currently connected
  final bool connected;

  /// Time that a last sync has fully completed, if any
  /// Currently this is reset to null after a restart
  final DateTime? lastSyncedAt;

  const SyncStatus({required this.connected, required this.lastSyncedAt});

  @override
  bool operator ==(Object other) {
    return (other is SyncStatus &&
        other.connected == connected &&
        other.lastSyncedAt == lastSyncedAt);
  }

  @override
  int get hashCode {
    return Object.hash(connected, lastSyncedAt);
  }

  @override
  String toString() {
    return "SyncStatus<connected: $connected lastSyncedAt: $lastSyncedAt>";
  }
}

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

  DateTime? lastSyncedAt;

  StreamingSyncImplementation(
      {required this.adapter,
      required this.credentialsCallback,
      this.invalidCredentialsCallback,
      required this.uploadCrud,
      required this.updateStream}) {
    _client = http.Client();
    statusStream = _statusStreamController.stream;
  }

  Future<void> streamingSync() async {
    print('${DateTime.now()} Start Sync');
    crudLoop();
    while (true) {
      try {
        await streamingSyncIteration();
        // Continue immediately
      } catch (e, stacktrace) {
        // TODO: Better error reporting
        print(e);
        print(stacktrace);

        _statusStreamController
            .add(SyncStatus(connected: false, lastSyncedAt: lastSyncedAt));
        await Future.delayed(const Duration(milliseconds: 5000));
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
        print(e);
        print(stacktrace);
        await Future.delayed(const Duration(milliseconds: 5000));
      }
    }
  }

  Future<bool> uploadCrudBatch() async {
    if (adapter.hasCrud()) {
      await uploadCrud();
      return false;
    } else {
      final batch = adapter.getCrudBatch();
      if (batch == null) {
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

    return false;
  }

  Future<String> getWriteCheckpoint() async {
    final credentials = await credentialsCallback();
    if (credentials == null) {
      throw AssertionError("Not logged in");
    }
    final uri = credentials.endpointUri('write-checkpoint.json');

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
      throw HttpException(response.reasonPhrase ?? "Request failed", uri: uri);
    }

    final body = convert.jsonDecode(response.body);
    return body['checkpoint'] as String;
  }

  Future<bool> streamingSyncIteration() async {
    adapter.startSession();
    final bucketEntries = adapter.getBucketStates();

    Map<String, String> bucketStates = {};

    for (final entry in bucketEntries) {
      bucketStates[entry.bucket] = entry.opId;
    }

    final List<BucketRequest> req = [];
    for (var entry in bucketStates.entries) {
      req.add(BucketRequest(entry.key, entry.value));
    }

    Checkpoint? targetCheckpoint;
    Checkpoint? validatedCheckpoint;
    Checkpoint? appliedCheckpoint;

    var requestStream = streamingSyncRequest(StreamingSyncRequest(req));

    var merged = addBroadcast(requestStream, _localPingController.stream);

    await for (var line in merged) {
      _statusStreamController
          .add(SyncStatus(connected: true, lastSyncedAt: lastSyncedAt));
      if (line is Checkpoint) {
        targetCheckpoint = line;
        final Set<String> bucketsToDelete = {...bucketStates.keys};
        final Map<String, String> newBuckets = {};
        for (final checksum in line.checksums) {
          newBuckets[checksum.bucket] = bucketStates[checksum.bucket] ?? '0';
          bucketsToDelete.remove(checksum.bucket);
        }
        if (bucketsToDelete.isNotEmpty) {
          // console.debug('Remove buckets', [...bucketsToDelete]);
        }
        bucketStates = newBuckets;
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

        final newCheckpoint = Checkpoint(diff.lastOpId, [...newBuckets.values]);
        targetCheckpoint = newCheckpoint;
      } else if (line is SyncBucketData) {
        await adapter.saveSyncData(SyncDataBatch([line]));
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
    }
    return true;
  }

  Stream<T> addBroadcast<T>(Stream<T> a, Stream<T> broadcast) {
    var controller = StreamController<T>();

    StreamSubscription<T>? sub1;
    StreamSubscription<T>? sub2;

    void close() {
      controller.close();
      sub1!.cancel();
      sub2!.cancel();
    }

    // TODO: backpressure?
    sub1 = a.listen((event) {
      controller.add(event);
    }, onDone: () {
      close();
    }, onError: (e) {
      controller.addError(e);
      close();
    });

    sub2 = broadcast.listen((event) {
      controller.add(event);
    }, onDone: () {
      close();
    }, onError: (e) {
      controller.addError(e);
      close();
    });

    return controller.stream;
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
      throw HttpException(res.reasonPhrase ?? 'Invalid http response',
          uri: uri);
    }

    Future<void>? credentialsInvalidation;
    bool haveInvalidated = false;

    // Note: The response stream is automatically closed when this loop errors
    await for (var line in ndjson(res.stream)) {
      if (line != null) {
        final parsed = parseStreamingSyncLine(line as Map<String, dynamic>);
        yield parsed;
      }
      if (haveInvalidated) {
        // Start new connection
        break;
      }
      if (credentials.expiresSoon() &&
          credentialsInvalidation == null &&
          invalidCredentialsCallback != null) {
        credentialsInvalidation = invalidCredentialsCallback!().then((_) {
          haveInvalidated = true;
        }, onError: (_) {
          // Ignore
        });
      }
    }
  }
}

class StreamingSyncCheckpoint {
  Checkpoint checkpoint;

  StreamingSyncCheckpoint(this.checkpoint);

  StreamingSyncCheckpoint.fromJson(Map<String, dynamic> json)
      : checkpoint = Checkpoint.fromJson(json);
}

class StreamingSyncCheckpointDiff {
  String lastOpId;
  List<BucketChecksum> updatedBuckets;
  List<String> removedBuckets;

  StreamingSyncCheckpointDiff(
      this.lastOpId, this.updatedBuckets, this.removedBuckets);

  StreamingSyncCheckpointDiff.fromJson(Map<String, dynamic> json)
      : lastOpId = json['last_op_id'],
        updatedBuckets = (json['updated_buckets'] as List)
            .map((e) => BucketChecksum.fromJson(e))
            .toList(),
        removedBuckets = List<String>.from(json['removed_buckets']);
}

class StreamingSyncCheckpointComplete {
  String lastOpId;

  StreamingSyncCheckpointComplete(this.lastOpId);

  StreamingSyncCheckpointComplete.fromJson(Map<String, dynamic> json)
      : lastOpId = json['last_op_id'];
}

Object? parseStreamingSyncLine(Map<String, dynamic> line) {
  if (line.containsKey('checkpoint')) {
    return Checkpoint.fromJson(line['checkpoint']);
  } else if (line.containsKey('checkpoint_diff')) {
    return StreamingSyncCheckpointDiff.fromJson(line['checkpoint_diff']);
  } else if (line.containsKey('checkpoint_complete')) {
    return StreamingSyncCheckpointComplete.fromJson(
        line['checkpoint_complete']);
  } else if (line.containsKey('data')) {
    return SyncBucketData.fromJson(line['data']);
  } else {
    return null;
  }
}

Stream<Object?> ndjson(ByteStream input) {
  final textInput = input.transform(convert.utf8.decoder);
  final lineInput = textInput.transform(const convert.LineSplitter());
  final jsonInput = lineInput.transform(StreamTransformer.fromHandlers(
      handleData: (String data, EventSink<dynamic> sink) {
    sink.add(convert.jsonDecode(data));
  }));
  return jsonInput;
}

class StreamingSyncRequest {
  List<BucketRequest> buckets;
  bool includeChecksum = true;

  StreamingSyncRequest(this.buckets);

  Map<String, dynamic> toJson() =>
      {'buckets': buckets, 'include_checksum': includeChecksum};
}

class BucketRequest {
  String name;
  String after;

  BucketRequest(this.name, this.after);

  Map<String, dynamic> toJson() => {
        'name': name,
        'after': after,
      };
}
