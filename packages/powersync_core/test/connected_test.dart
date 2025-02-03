@TestOn('!browser')
library;

// This test uses a local server which is possible to control in Web via hybrid main,
// but this makes the test significantly more complex.
import 'dart:async';

import 'package:powersync_core/powersync_core.dart';
import 'package:test/test.dart';

import 'server/sync_server/mock_sync_server.dart';
import 'streaming_sync_test.dart';
import 'utils/abstract_test_utils.dart';
import 'utils/test_utils_impl.dart';

final testUtils = TestUtils();

void main() {
  group('connected tests', () {
    late String path;
    setUp(() async {
      path = testUtils.dbPath();
    });

    tearDown(() async {
      await testUtils.cleanDb(path: path);
    });

    createTestServer() async {
      final testServer = TestHttpServerHelper();
      await testServer.start();
      addTearDown(() => testServer.stop());
      return testServer;
    }

    test('should connect to mock PowerSync instance', () async {
      final testServer = await createTestServer();
      final connector = TestConnector(() async {
        return PowerSyncCredentials(
            endpoint: testServer.uri.toString(),
            token: 'token not used here',
            expiresAt: DateTime.now());
      });

      final db = PowerSyncDatabase.withFactory(
          await testUtils.testFactory(path: path),
          schema: defaultSchema,
          maxReaders: 3);
      addTearDown(() => {db.close()});
      await db.initialize();

      final connectedCompleter = Completer<void>();

      db.statusStream.listen((status) {
        if (status.connected) {
          connectedCompleter.complete();
        }
      });

      // Add a basic command for the test server to send
      testServer.addEvent('{"token_expires_in": 3600}\n');

      await db.connect(connector: connector);
      await connectedCompleter.future;

      expect(db.connected, isTrue);
      await db.disconnect();
    });

    test('should trigger uploads when connection is re-established', () async {
      int uploadCounter = 0;
      var uploadTriggeredCompleter = Completer<void>();
      final testServer = await createTestServer();
      final connector = TestConnector(() async {
        return PowerSyncCredentials(
            endpoint: testServer.uri.toString(),
            token: 'token not used here',
            expiresAt: DateTime.now());
      }, uploadData: (database) async {
        uploadCounter++;
        uploadTriggeredCompleter.complete();
        throw Exception('No uploads occur here');
      });

      final db = PowerSyncDatabase.withFactory(
          await testUtils.testFactory(path: path),
          schema: defaultSchema,
          maxReaders: 3);
      // Shorter retry delay, to speed up tests
      db.retryDelay = Duration(milliseconds: 10);
      addTearDown(() => {db.close()});
      await db.initialize();

      // Create an item which should trigger an upload.
      await db.execute(
          'INSERT INTO customers (id, name) VALUES (uuid(), ?)', ['steven']);

      // Create a new completer to await the next upload
      uploadTriggeredCompleter = Completer();

      // Connect the PowerSync instance
      final connectedCompleter = Completer<void>();
      // The first connection attempt will fail
      final connectedErroredCompleter = Completer<void>();

      db.statusStream.listen((status) {
        if (status.connected && !connectedCompleter.isCompleted) {
          connectedCompleter.complete();
        }
        if (status.downloadError != null &&
            !connectedErroredCompleter.isCompleted) {
          connectedErroredCompleter.complete();
        }
      });

      // The first command will not be valid, this simulates a failed connection
      testServer.addEvent('asdf\n');
      await db.connect(connector: connector);

      // The connect operation should have triggered an upload (even though it fails to connect)
      await uploadTriggeredCompleter.future;
      expect(uploadCounter, equals(1));
      // Create a new completer for the next iteration
      uploadTriggeredCompleter = Completer();

      // Connection attempt should initially fail
      await connectedErroredCompleter.future;
      expect(db.currentStatus.anyError, isNotNull);

      // Now send a valid command. Which will result in successful connection
      await testServer.clearEvents();
      testServer.addEvent('{"token_expires_in": 3600}\n');
      await connectedCompleter.future;
      expect(db.connected, isTrue);

      await uploadTriggeredCompleter.future;
      expect(uploadCounter, equals(2));

      await db.disconnect();
    });

    test('should persist local changes when there is no write checkpoint',
        () async {
      final testServer = await createTestServer();
      final connector = TestConnector(() async {
        return PowerSyncCredentials(
            endpoint: testServer.uri.toString(),
            token: 'token not used here',
            expiresAt: DateTime.now());
      }, uploadData: (database) async {
        final tx = await database.getNextCrudTransaction();
        if (tx != null) {
          await tx.complete();
        }
      });

      final db = PowerSyncDatabase.withFactory(
          await testUtils.testFactory(path: path),
          schema: defaultSchema,
          maxReaders: 3);
      addTearDown(() => {db.close()});
      await db.initialize();

      // Create an item which should trigger an upload.
      await db.execute(
          'INSERT INTO customers (id, name) VALUES (uuid(), ?)', ['steven']);

      // Manually simulate upload before connecting.
      // This is simpler than doing this via connect() and waiting for it to complete.
      await connector.uploadData(db);

      // Check that the data is present locally
      expect(
          await db.getAll('select name from customers'),
          equals([
            {'name': 'steven'}
          ]));

      // Connect and send a checkpoint back, but no write checkpoint.
      testServer
          .addEvent('{"checkpoint": {"last_op_id": "10", "buckets": []}}\n');
      testServer.addEvent('{"checkpoint_complete": {"last_op_id": "10"}}\n');

      // Now connect and wait for sync to complete
      await db.connect(connector: connector);
      await db.statusStream
          .firstWhere((status) => status.connected && status.downloading);
      await Future<void>.delayed(Duration(milliseconds: 20));
      expect(
          await db.getAll('select name from customers'),
          equals([
            {'name': 'steven'}
          ]));
    });

    test('should remove local changes when there a write checkpoint', () async {
      // The only difference between this and the one above, is that the synced
      // checkpoint here contains a write checkpoint, matching the write-checkpoint2.json
      // API. This will trigger the local changes to be removed.
      final testServer = await createTestServer();
      final connector = TestConnector(() async {
        return PowerSyncCredentials(
            endpoint: testServer.uri.toString(),
            token: 'token not used here',
            expiresAt: DateTime.now());
      }, uploadData: (database) async {
        final tx = await database.getNextCrudTransaction();
        if (tx != null) {
          await tx.complete();
        }
      });

      final db = PowerSyncDatabase.withFactory(
          await testUtils.testFactory(path: path),
          schema: defaultSchema,
          maxReaders: 3);
      addTearDown(() => {db.close()});
      await db.initialize();

      // Create an item which should trigger an upload.
      await db.execute(
          'INSERT INTO customers (id, name) VALUES (uuid(), ?)', ['steven']);

      // Manually simulate upload before connecting.
      // This is simpler than doing this via connect() and waiting for it to complete.
      await connector.uploadData(db);

      // Check that the data is present locally
      expect(
          await db.getAll('select name from customers'),
          equals([
            {'name': 'steven'}
          ]));

      // Connect and send a checkpoint back, but no write checkpoint.
      testServer.addEvent(
          '{"checkpoint": {"last_op_id": "10", "buckets": [], "write_checkpoint": "10"}}\n');
      testServer.addEvent('{"checkpoint_complete": {"last_op_id": "10"}}\n');

      // Now connect and wait for sync to complete
      await db.connect(connector: connector);
      await db.statusStream
          .firstWhere((status) => status.connected && status.downloading);
      await Future<void>.delayed(Duration(milliseconds: 20));
      expect(await db.getAll('select name from customers'), equals([]));
    });
  });
}
