import 'dart:math';

import 'package:powersync/powersync.dart';
import 'package:powersync/src/database_utils.dart';
import 'package:test/test.dart';

import 'util.dart';

const testSchema = Schema([
  Table('assets', [
    Column.text('created_at'),
    Column.text('make'),
    Column.text('model'),
    Column.text('serial_number'),
    Column.integer('quantity'),
    Column.text('user_id'),
    Column.text('customer_id'),
    Column.text('description'),
  ], indexes: [
    Index('makemodel', [IndexedColumn('make'), IndexedColumn('model')])
  ]),
  Table('customers', [Column.text('name'), Column.text('email')]),
  Table('other_customers', [Column.text('name'), Column.text('email')]),
]);

void main() {
  setupLogger();

  group('Query Watch Tests', () {
    late String path;

    setUp(() async {
      path = dbPath();
      await cleanDb(path: path);
    });

    test('Basic Setup', () async {
      final powersync = await setupPowerSync(path: path, schema: testSchema);

      final tables = await getSourceTables(powersync,
          'SELECT * FROM assets INNER JOIN customers ON assets.customer_id = customers.id');
      expect(tables, equals({'ps_data__assets', 'ps_data__customers'}));

      final tables2 = await getSourceTables(powersync,
          'SELECT count() FROM assets INNER JOIN "other_customers" AS oc ON assets.customer_id = oc.id AND assets.make = oc.name');
      expect(tables2, equals({'ps_data__assets', 'ps_data__other_customers'}));
    });

    test('watch', () async {
      final powersync = await setupPowerSync(path: path, schema: testSchema);

      const baseTime = 20;

      const throttleDuration = Duration(milliseconds: baseTime);

      final stream = powersync.watch(
          'SELECT count() AS count FROM assets INNER JOIN customers ON customers.id = assets.customer_id',
          throttle: throttleDuration);

      var id = uuid.v4();
      await powersync.execute(
          'INSERT INTO customers(id, name) VALUES (?, ?)', [id, 'a customer']);

      var done = false;
      inserts() async {
        while (!done) {
          await powersync.execute(
              'INSERT INTO assets(id, make, customer_id) VALUES (uuid(), ?, ?)',
              ['test', id]);
          await Future.delayed(
              Duration(milliseconds: Random().nextInt(baseTime * 2)));
        }
      }

      const numberOfQueries = 10;

      inserts();
      try {
        List<DateTime> times = [];
        final results = await stream.take(numberOfQueries).map((e) {
          times.add(DateTime.now());
          return e;
        }).toList();

        var lastCount = 0;
        for (var r in results) {
          final count = r.first['count'];
          // This is not strictly incrementing, since we can't guarantee the
          // exact order between reads and writes.
          // We can guarantee that there will always be a read after the last write,
          // but the previous read may have been after the same write in some cases.
          expect(count, greaterThanOrEqualTo(lastCount));
          lastCount = count;
        }

        // The number of read queries must not be greater than the number of writes overall.
        expect(numberOfQueries, lessThanOrEqualTo(results.last.first['count']));

        DateTime? lastTime;
        for (var r in times) {
          if (lastTime != null) {
            var diff = r.difference(lastTime);
            expect(diff, greaterThanOrEqualTo(throttleDuration));
          }
          lastTime = r;
        }
      } finally {
        done = true;
      }
    });
  });
}
