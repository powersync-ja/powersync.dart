@TestOn('!browser')
// TODO setup hybrid server
import 'dart:async';
import 'dart:io';

import 'package:powersync/powersync.dart';
import 'package:test/test.dart';

import 'test_server.dart';
import 'utils/test_utils_impl.dart';

final testUtils = TestUtils();

class TestConnector extends PowerSyncBackendConnector {
  final Function _fetchCredentials;

  TestConnector(this._fetchCredentials);

  @override
  Future<PowerSyncCredentials?> fetchCredentials() {
    return _fetchCredentials();
  }

  @override
  Future<void> uploadData(PowerSyncDatabase database) async {}
}

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

    /// TODO this test intermittently freezes
    // test('full powersync reconnect', () async {
    //   // Test repeatedly creating new PowerSync connections, then disconnect
    //   // and close the connection.
    //   final random = Random();

    //   for (var i = 0; i < 10; i++) {
    //     var server = await createServer();

    //     credentialsCallback() async {
    //       final endpoint = 'http://${server.address.host}:${server.port}';
    //       return PowerSyncCredentials(
    //           endpoint: endpoint,
    //           token: 'token',
    //           userId: 'u1',
    //           expiresAt: DateTime.now());
    //     }

    //     final pdb = await testUtils.setupPowerSync(path: path);
    //     pdb.retryDelay = Duration(milliseconds: 5000);
    //     var connector = TestConnector(credentialsCallback);
    //     pdb.connect(connector: connector);

    //     await Future.delayed(Duration(milliseconds: random.nextInt(100)));
    //     if (random.nextBool()) {
    //       server.close(force: true).ignore();
    //     }

    //     await pdb.close();

    //     server.close(force: true).ignore();
    //   }
    // });

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

      HttpServer? server;

      credentialsCallback() async {
        if (server == null) {
          throw AssertionError('No active server');
        }
        final endpoint = 'http://${server.address.host}:${server.port}';
        return PowerSyncCredentials(
            endpoint: endpoint,
            token: 'token',
            userId: 'u1',
            expiresAt: DateTime.now());
      }

      final pdb = await testUtils.setupPowerSync(path: path);
      pdb.retryDelay = const Duration(milliseconds: 5);
      var connector = TestConnector(credentialsCallback);
      pdb.connect(connector: connector);

      for (var i = 0; i < 10; i++) {
        server = await createServer();

        // var stream = impl.streamingSyncRequest(StreamingSyncRequest([]));
        // 2ms: HttpException: HttpServer is not bound to a socket
        // 20ms: Connection closed while receiving data
        await Future.delayed(Duration(milliseconds: 20));
        server.close(force: true).ignore();
      }
      await pdb.close();
    });
  });
}
