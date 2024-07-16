import 'package:powersync/powersync.dart';
import 'package:test/test.dart';
import 'streaming_sync_test.dart';
import 'utils/test_utils_impl.dart';
import 'watch_test.dart';

final testUtils = TestUtils();

void main() {
  group('Disconnect Tests', () {
    late String path;

    setUp(() async {
      path = testUtils.dbPath();
      await testUtils.cleanDb(path: path);
    });

    test('Multiple calls to disconnect', () async {
      final db = await testUtils.setupPowerSync(path: path, schema: testSchema);

      credentialsCallback() async {
        // A blank endpoint will fail, but that's okay for this test
        final endpoint = '';
        return PowerSyncCredentials(
            endpoint: endpoint,
            token: 'token',
            userId: 'u1',
            expiresAt: DateTime.now());
      }

      db.retryDelay = Duration(milliseconds: 5000);
      var connector = TestConnector(credentialsCallback);
      await db.connect(connector: connector);

      // Call disconnect multiple times, each Future should resolve
      final disconnect1 = db.disconnect();
      final disconnect2 = db.disconnect();

      await expectLater(disconnect1, completes);
      await expectLater(disconnect2, completes);
    }, timeout: Timeout(Duration(seconds: 60)));

    test('disconnectAndClear clears DB', () async {
      final db = await testUtils.setupPowerSync(path: path, schema: testSchema);

      await db.execute(
          'INSERT INTO customers (id, name, email) VALUES(uuid(), ?, ?)',
          ['Steven', 'steven@journeyapps.com']);

      final getCustomersQuery = 'SELECT * from customers';
      final initialCustomers = await db.getAll(getCustomersQuery);
      expect(initialCustomers.length, equals(1));

      await db.disconnectAndClear();

      final finalCustomers = await db.getAll(getCustomersQuery);
      expect(finalCustomers.length, equals(0));
    });
  });
}
