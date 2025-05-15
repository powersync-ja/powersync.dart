import 'package:powersync_core/powersync_core.dart';
import 'package:powersync_core/sqlite_async.dart';
import 'package:test/test.dart';
import 'utils/abstract_test_utils.dart';
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

      // ignore: deprecated_member_use_from_same_package
      db.retryDelay = Duration(milliseconds: 5000);
      var connector = TestConnector(credentialsCallback);
      await db.connect(connector: connector);

      // Call disconnect multiple times, each Future should resolve
      final disconnect1 = db.disconnect();
      final disconnect2 = db.disconnect();

      await expectLater(disconnect1, completes);
      await expectLater(disconnect2, completes);
    });

    test('disconnectAndClear clears DB', () async {
      final db = await testUtils.setupPowerSync(path: path, schema: testSchema);

      await db.execute(
          'INSERT INTO customers (id, name, email) VALUES(uuid(), ?, ?)',
          ['Steven', 'steven@journeyapps.com']);

      final getCustomersQuery = 'SELECT * from customers';
      final initialCustomers = await db.getAll(getCustomersQuery);
      expect(initialCustomers.length, equals(1));

      final changesFuture = db
          .onChange({'customers'}, triggerImmediately: false)
          .take(1)
          .toList();

      await db.disconnectAndClear();

      final finalCustomers = await db.getAll(getCustomersQuery);
      expect(finalCustomers.length, equals(0));

      expect(db.currentStatus.lastSyncedAt, equals(null));
      expect(db.currentStatus.hasSynced, equals(false));

      final changes = await changesFuture;
      expect(changes.first, equals(UpdateNotification({'customers'})));
    });
  });
}
