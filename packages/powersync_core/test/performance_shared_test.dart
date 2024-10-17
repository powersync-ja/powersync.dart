import 'package:powersync_core/powersync_core.dart';
import 'package:test/test.dart';

import 'utils/test_utils_impl.dart';

final testUtils = TestUtils();

const pschema = Schema([
  Table.localOnly('assets', [
    Column.text('created_at'),
    Column.text('make'),
    Column.text('model'),
    Column.text('serial_number'),
    Column.integer('quantity'),
    Column.text('user_id'),
    Column.text('customer_id'),
    Column.text('description'),
  ]),
  Table.localOnly('customers', [Column.text('name'), Column.text('email')])
]);

void main() {
  group('Performance Tests', () {
    late String path;

    setUp(() async {
      path = testUtils.dbPath();
      await testUtils.cleanDb(path: path);
    });

    tearDown(() async {
      // await cleanDb(path: path);
    });

    // Manual tests
    test('Insert Performance 1 - direct', () async {
      final db = PowerSyncDatabase.withFactory(
          await testUtils.testFactory(path: path),
          schema: pschema);
      await db.initialize();
      final timer = Stopwatch()..start();

      for (var i = 0; i < 1000; i++) {
        await db.execute(
            'INSERT INTO customers(id, name, email) VALUES(uuid(), ?, ?)',
            ['Test User', 'user@example.org']);
      }
      print("Completed sequential inserts in ${timer.elapsed}");
      expect(await db.get('SELECT count(*) as count FROM customers'),
          equals({'count': 1000}));
    });

    test('Insert Performance 2 - writeTransaction', () async {
      final db = PowerSyncDatabase.withFactory(
          await testUtils.testFactory(path: path),
          schema: pschema);
      await db.initialize();
      final timer = Stopwatch()..start();

      await db.writeTransaction((tx) async {
        for (var i = 0; i < 1000; i++) {
          await tx.execute(
              'INSERT INTO customers(id, name, email) VALUES(uuid(), ?, ?)',
              ['Test User', 'user@example.org']);
        }
      });
      print("Completed transaction inserts in ${timer.elapsed}");
      expect(await db.get('SELECT count(*) as count FROM customers'),
          equals({'count': 1000}));
    });

    test('Insert Performance 4 - pipelined', () async {
      final db = PowerSyncDatabase.withFactory(
          await testUtils.testFactory(path: path),
          schema: pschema);
      await db.initialize();
      final timer = Stopwatch()..start();

      await db.writeTransaction((tx) async {
        List<Future> futures = [];
        for (var i = 0; i < 1000; i++) {
          var future = tx.execute(
              'INSERT INTO customers(id, name, email) VALUES(uuid(), ?, ?)',
              ['Test User', 'user@example.org']);
          futures.add(future);
        }
        await Future.wait(futures);
      });
      print("Completed pipelined inserts in ${timer.elapsed}");
      expect(await db.get('SELECT count(*) as count FROM customers'),
          equals({'count': 1000}));
    });

    test('Insert Performance 5 - executeBatch', () async {
      final db = PowerSyncDatabase.withFactory(
          await testUtils.testFactory(path: path),
          schema: pschema);
      await db.initialize();
      final timer = Stopwatch()..start();

      var parameters = List.generate(
          1000, (index) => [uuid.v4(), 'Test user', 'user@example.org']);
      await db.executeBatch(
          'INSERT INTO customers(id, name, email) VALUES(?, ?, ?)', parameters);
      print("Completed executeBatch in ${timer.elapsed}");
      expect(await db.get('SELECT count(*) as count FROM customers'),
          equals({'count': 1000}));
    });
  });
}
