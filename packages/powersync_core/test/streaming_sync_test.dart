@TestOn('!browser')
library;

// TODO setup hybrid server
import 'dart:async';
import 'dart:math';

import 'package:logging/logging.dart';
import 'package:powersync_core/powersync_core.dart';
import 'package:test/test.dart';

import 'server/sync_server/in_memory_sync_server.dart';
import 'test_server.dart';
import 'utils/abstract_test_utils.dart';
import 'utils/test_utils_impl.dart';

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

      final pdb =
          await testUtils.setupPowerSync(path: path, logger: ignoreLogger);
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

      final pdb =
          await testUtils.setupPowerSync(path: path, logger: ignoreLogger);
      const options = SyncOptions(retryDelay: Duration(seconds: 5));
      final connector = TestConnector(expectAsync0(() async {
        return PowerSyncCredentials(endpoint: server.endpoint, token: 'token');
      }));

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
          path: path, logger: ignoreLogger, initialize: false);
      const options = SyncOptions(retryDelay: Duration(seconds: 5));

      await pdb.connect(
        connector: TestConnector(() async {
          return PowerSyncCredentials(
              endpoint: server.endpoint, token: 'token');
        }),
        options: options,
      );

      await expectLater(
        pdb.statusStream,
        emitsThrough(
            isA<SyncStatus>().having((e) => e.connected, 'connected', isTrue)),
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
              endpoint: server.endpoint, token: 'token');
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
              Duration(milliseconds: random.nextInt(10)));
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
  });
}
