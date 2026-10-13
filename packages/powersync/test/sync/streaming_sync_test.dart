@TestOn('!browser')
library;

// TODO setup hybrid server
import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:async/async.dart';
import 'package:logging/logging.dart';
import 'package:powersync/powersync.dart';
import 'package:powersync/src/abort_controller.dart';
import 'package:powersync/src/connector.dart';
import 'package:powersync/src/database/native/native_powersync_database.dart';
import 'package:powersync/src/sync/options.dart';
import 'package:sqlite_async/sqlite_async.dart';
import 'package:shelf/shelf.dart';
import 'package:test/test.dart';

import '../server/sync_server/in_memory_sync_server.dart';
import '../test_server.dart';
import '../utils/abstract_test_utils.dart';
import '../utils/test_utils_impl.dart';
import 'utils.dart';

final testUtils = TestUtils();

void main() {
  group('Streaming Sync Test', () {
    late String path;

    setUp(() async {
      path = testUtils.dbPath();
      await testUtils.cleanDb(path: path);
    });

    tearDown(() async {
      await testUtils.cleanDb(path: path);
    });

    test('repeated connect and disconnect calls', () async {
      final random = Random();
      final server = await createServer();
      final ignoreLogger = Logger.detached('powersync.test');

      final pdb = await testUtils.setupPowerSync(
        path: path,
        logger: ignoreLogger,
      );
      const options = SyncOptions(retryDelay: Duration(seconds: 5));
      final connector = TestConnector(() async {
        return PowerSyncCredentials(endpoint: server.endpoint, token: 'token');
      });

      Duration nextDelay() {
        return Duration(milliseconds: random.nextInt(100));
      }

      Future<void> connectAndDisconnect() async {
        for (var i = 0; i < 10; i++) {
          await Future<void>.delayed(nextDelay());
          await pdb.connect(connector: connector, options: options);

          await Future<void>.delayed(nextDelay());
          await pdb.disconnect();
        }
      }

      // Create a bunch of tasks calling connect and disconnect() concurrently.
      await Future.wait([for (var i = 0; i < 10; i++) connectAndDisconnect()]);

      expect(server.maxConnectionCount, lessThanOrEqualTo(1));
      server.close();
    });

    test('can disconnect in fetchCredentials', () async {
      final service = MockSyncService();
      final server = await createServer(mockSyncService: service);
      final ignoreLogger = Logger.detached('powersync.test');

      final pdb = await testUtils.setupPowerSync(
        path: path,
        logger: ignoreLogger,
      );
      const options = SyncOptions(retryDelay: Duration(seconds: 5));
      final connector = TestConnector(
        expectAsync0(() async {
          return PowerSyncCredentials(
            endpoint: server.endpoint,
            token: 'token',
          );
        }),
      );

      await pdb.connect(connector: connector, options: options);
      while (server.connectionCount != 1) {
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }

      service.addKeepAlive(60);

      final didDisconnect = Completer<void>();

      connector.fetchCredentialsCallback = expectAsync0(() async {
        didDisconnect.complete(pdb.disconnect());

        throw 'deliberate disconnect';
      });

      service.addKeepAlive(0);
      await didDisconnect.future;
      expect(pdb.currentStatus.connected, isFalse);
      // The error should be cleared after calling disconnect
      expect(pdb.currentStatus.downloadError, isNull);

      // Wait for a short while to make sure the database doesn't reconnect.
      for (var i = 0; i < 10; i++) {
        expect(pdb.currentStatus.connecting, isFalse);
      }
    });

    test('can connect as initial operation', () async {
      final server = await createServer();
      final ignoreLogger = Logger.detached('powersync.test');

      final pdb = await testUtils.setupPowerSync(
        path: path,
        logger: ignoreLogger,
        initialize: false,
      );
      const options = SyncOptions(retryDelay: Duration(seconds: 5));

      await pdb.connect(
        connector: TestConnector(() async {
          return PowerSyncCredentials(
            endpoint: server.endpoint,
            token: 'token',
          );
        }),
        options: options,
      );

      await expectLater(
        pdb.statusStream,
        emitsThrough(
          isA<SyncStatus>().having((e) => e.connected, 'connected', isTrue),
        ),
      );
    });

    test('full powersync reconnect', () async {
      // Test repeatedly creating new PowerSync connections, then disconnect
      // and close the connection.
      final random = Random();

      for (var i = 0; i < 10; i++) {
        var server = await createServer();

        credentialsCallback() async {
          return PowerSyncCredentials(
            endpoint: server.endpoint,
            token: 'token',
          );
        }

        final pdb = await testUtils.setupPowerSync(path: path);
        const options = SyncOptions(retryDelay: Duration(seconds: 5));
        var connector = TestConnector(credentialsCallback);
        pdb.connect(connector: connector, options: options);

        await Future<void>.delayed(Duration(milliseconds: random.nextInt(100)));
        if (random.nextBool()) {
          server.close();
        }

        await pdb.close();

        // Give some time for connections to close
        final watch = Stopwatch()..start();
        while (server.connectionCount != 0 && watch.elapsedMilliseconds < 100) {
          await Future<void>.delayed(
            Duration(milliseconds: random.nextInt(10)),
          );
        }

        expect(server.connectionCount, equals(0));
        expect(server.maxConnectionCount, lessThanOrEqualTo(1));

        server.close();
      }
    });

    test('powersync connection errors', () async {
      // Test repeatedly killing the streaming connection
      // Errors like this are expected:
      //
      //   [PowerSync] WARNING: 2023-06-29 16:05:24.810002: Sync error
      //   Connection closed while receiving data
      //   Write failed
      //   Connection refused
      //
      // Errors like this are not okay:
      // [PowerSync] WARNING: 2023-06-29 16:10:17.667537: Sync Isolate error
      // [Connection closed while receiving data, #0      IOClient.send.<anonymous closure> (package:http/src/io_client.dart:76:13)

      TestServer? server;

      credentialsCallback() async {
        if (server == null) {
          throw AssertionError('No active server');
        }
        return PowerSyncCredentials(endpoint: server.endpoint, token: 'token');
      }

      final pdb = await testUtils.setupPowerSync(path: path);
      const options = SyncOptions(retryDelay: Duration(seconds: 5));
      var connector = TestConnector(credentialsCallback);
      pdb.connect(connector: connector, options: options);

      for (var i = 0; i < 10; i++) {
        server = await createServer();

        // var stream = impl.streamingSyncRequest(StreamingSyncRequest([]));
        // 2ms: HttpException: HttpServer is not bound to a socket
        // 20ms: Connection closed while receiving data
        await Future<void>.delayed(Duration(milliseconds: 20));
        server.close();
      }
      await pdb.close();
    });

    test('multiple connect calls', () async {
      // Test calling connect() multiple times.
      // We check that this does not cause multiple connections to be opened concurrently.
      final random = Random();
      var server = await createServer();

      credentialsCallback() async {
        return PowerSyncCredentials(endpoint: server.endpoint, token: 'token');
      }

      final pdb = await testUtils.setupPowerSync(path: path);
      const options = SyncOptions(retryDelay: Duration(seconds: 5));
      var connector = TestConnector(credentialsCallback);
      pdb.connect(connector: connector, options: options);
      pdb.connect(connector: connector, options: options);

      final watch = Stopwatch()..start();

      // Wait for at least one connection
      while (server.connectionCount < 1 && watch.elapsedMilliseconds < 500) {
        await Future<void>.delayed(Duration(milliseconds: random.nextInt(10)));
      }
      // Give some time for a second connection if any
      await Future<void>.delayed(Duration(milliseconds: random.nextInt(50)));

      await pdb.close();

      // Give some time for connections to close
      while (server.connectionCount != 0 && watch.elapsedMilliseconds < 1000) {
        await Future<void>.delayed(Duration(milliseconds: random.nextInt(10)));
      }

      expect(server.connectionCount, equals(0));
      expect(server.maxConnectionCount, equals(1));

      server.close();
    });

    test('can report unsendable errors in sync status', () async {
      final pdb = await testUtils.setupPowerSync(path: path);
      final exception = _UnsendableException();

      final connector = TestConnector(() async => throw exception);
      final statusChanges = StreamQueue(pdb.statusStream);
      await pdb.connect(connector: connector);
      await expectLater(
        statusChanges,
        emitsThrough(
          isA<SyncStatus>().having(
            (e) => e.downloadError,
            'downloadError',
            isNotNull,
          ),
        ),
      );
      await statusChanges.cancel();

      expect(pdb.currentStatus.downloadError, exception);
    });

    test('can use custom checkpoint requests', () async {
      final hadRequest = Completer<void>();
      final pdb = await testUtils.setupPowerSync(path: path);
      final server = await createServer();
      final connector = TestCustomCheckpointConnector(
        () async =>
            PowerSyncCredentials(endpoint: server.endpoint, token: 'token'),
        postCheckpointRequest: (clientId, requestId) async {
          expect(requestId, '1');
          hadRequest.complete();
          return requestId;
        },
      );

      await pdb.connect(
        connector: connector,
        options: SyncOptions(checkpointMode: CheckpointMode.requests()),
      );
      await hadRequest.future;
    });

    test('can request checkpoints', () async {
      final pdb = await testUtils.setupPowerSync(path: path);
      final server = await createServer();
      final connector = TestConnector(
        () async =>
            PowerSyncCredentials(endpoint: server.endpoint, token: 'token'),
      );

      await pdb.connect(
        connector: connector,
        options: SyncOptions(checkpointMode: CheckpointMode.requests()),
      );

      await pdb.requestCheckpoint();
    });

    test('can use custom platform', () async {
      final platform = _CountingPlatform();
      final pdb = await testUtils.setupPowerSync(
        path: path,
        platform: platform,
      );

      final server = await createServer();
      final connector = TestConnector(
        () async =>
            PowerSyncCredentials(endpoint: server.endpoint, token: 'token'),
      );

      await pdb.connect(
        connector: connector,
        options: SyncOptions(checkpointMode: CheckpointMode.requests()),
      );

      await expectLater(
        pdb.statusStream,
        emitsThrough(
          isA<SyncStatus>().having((e) => e.connected, 'connected', true),
        ),
      );
      await pdb.disconnect();

      Matcher wasLockedAtLeastOnce() {
        return isA<_CountingMutex>().having(
          (e) => e.timesLocked,
          'timesLocked',
          isPositive,
        );
      }

      expect(platform.mutexes, {
        'test-db/streaming_sync_test_can_use_custom_platform.db-sync':
            wasLockedAtLeastOnce(),
        'test-db/streaming_sync_test_can_use_custom_platform.db-crud':
            wasLockedAtLeastOnce(),
      });
    });

    test('forwards diagnostics events', () async {
      final service = MockSyncService();
      final server = await createServer(mockSyncService: service);

      final db = await testUtils.setupPowerSync(path: path);
      final abort = AbortController();
      final sync = await (db as NativePowerSyncDatabase).connectInternal(
        connector: TestConnector(() async {
          return PowerSyncCredentials(
            endpoint: server.endpoint,
            token: 'token',
          );
        }).toInternal(db),
        options: ResolvedSyncOptions(SyncOptions(enableDiagnostics: true)),
        initiallyActiveStreams: [],
        activeStreams: Stream.empty(),
        abort: abort,
        asyncWorkZone: Zone.current,
      );

      final didEmit = expectLater(
        sync.diagnostics.map(json.decode),
        emits({
          'BucketStateChange': {
            // We don't care about the exact diagnostic event, just that one is
            // emitted.
            'changes': [anything],
            'incremental': false,
          },
        }),
      );
      service
        ..addLine(checkpoint(lastOpId: 1, buckets: [bucketDescription('a')]))
        ..addLine({
          'data': {
            'bucket': 'a',
            'data': [
              {
                'checksum': 0,
                'data': json.encode({'name': 'custom list'}),
                'op': 'PUT',
                'op_id': '1',
                'object_id': 'my_list',
                'object_type': 'lists',
              },
            ],
          },
        })
        ..addLine(checkpointComplete(lastOpId: '1'));

      await db.waitForFirstSync();
      await abort.abort();
      await didEmit;
    });

    test('download-only smoke test', () async {
      final pdb = await testUtils.setupPowerSync(path: path);
      final server = await createServer();
      final connector = TestConnector(
        () async =>
            PowerSyncCredentials(endpoint: server.endpoint, token: 'token'),
      );

      await pdb.connect(
        connector: .downloadOnly(
          endpoint: server.endpoint,
          authenticator: connector,
        ),
      );
      await expectLater(
        pdb.statusStream,
        emitsThrough(
          isA<SyncStatus>().having((e) => e.connected, 'connected', isTrue),
        ),
      );
    });

    test('upload-only smoke test', () async {
      final server = TestServer();
      var receivedRequests = 0;
      await server.initCustom((request) async {
        receivedRequests++;
        return Response(400);
      });

      final pdb = await testUtils.setupPowerSync(path: path);
      final didUplod = Completer<void>();
      await pdb.connect(
        connector: .uploadOnly(
          MutationUploader((db) async {
            if (await db.getNextCrudTransaction() case final tx?) {
              didUplod.complete();
              await tx.complete();
            }
          }),
        ),
      );

      await pdb.execute('insert into customers (id, name) values (uuid(), ?)', [
        'customer',
      ]);
      await didUplod.future;
      expect(receivedRequests, isZero);
    });
  });
}

class _UnsendableException implements Exception {
  // ignore: unused_field
  final Object _unsendable = Completer<void>();

  @override
  String toString() => 'fetchCredentials failed';
}

final class _CountingPlatform extends PowerSyncPlatform {
  final Map<String, _CountingMutex> mutexes = {};

  @override
  Mutex namedMutex(String identifier) {
    return mutexes.putIfAbsent(identifier, _CountingMutex.new);
  }
}

final class _CountingMutex implements Mutex {
  final Mutex inner = Mutex.simple();
  var timesLocked = 0;

  @override
  Future<T> lock<T>(
    Future<T> Function() callback, {
    Future<void>? abortTrigger,
  }) {
    return inner.lock(() {
      timesLocked++;
      return Future.sync(callback);
    });
  }
}
