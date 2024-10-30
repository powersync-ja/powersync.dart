@TestOn('!browser')
// This test uses a local server which is possible to control in Web via hybrid main,
// but this makes the test significantly more complex.
import 'dart:async';

import 'package:powersync/powersync.dart';
import 'package:test/test.dart';

import 'server/sync_server/mock_sync_server.dart';
import 'streaming_sync_test.dart';
import 'utils/abstract_test_utils.dart';
import 'utils/test_utils_impl.dart';

final testUtils = TestUtils();

void main() {
  late TestHttpServerHelper testServer;
  late String path;

  setUp(() async {
    path = testUtils.dbPath();
    testServer = TestHttpServerHelper();
    await testServer.start();
  });

  tearDown(() async {
    await testUtils.cleanDb(path: path);
    await testServer.stop();
  });

  test('should connect to mock PowerSync instance', () async {
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
    await db.initialize();

    final connectedCompleter = Completer();

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
  });

  test('should trigger uploads when connection is re-established', () async {
    int uploadCounter = 0;
    Completer uploadTriggeredCompleter = Completer();

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
    await db.initialize();

    // Create an item which should trigger an upload.
    await db.execute(
        'INSERT INTO customers (id, name) VALUES (uuid(), ?)', ['steven']);

    // Create a new completer to await the next upload
    uploadTriggeredCompleter = Completer();

    // Connect the PowerSync instance
    final connectedCompleter = Completer();
    // The first connection attempt will fail
    final connectedErroredCompleter = Completer();

    db.statusStream.listen((status) {
      if (status.connected) {
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
  });
}
