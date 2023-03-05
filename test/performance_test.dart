import 'package:powersync/powersync.dart';
import 'package:powersync/src/background_database.dart';
import 'package:test/test.dart';

import 'util.dart';

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
  setupLogger();

  group('Performance Tests', () {
    late String path;

    setUp(() async {
      path = dbPath();
      await cleanDb(path: path);
    });

    tearDown(() async {
      // await cleanDb(path: path);
    });

    // Manual tests
    test('Insert Performance 1', () async {
      final db = PowerSyncDatabase(
          schema: pschema, path: path, sqliteSetup: testSetup, maxReaders: 3);
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

    test('Insert Performance 2', () async {
      final db = PowerSyncDatabase(
          schema: pschema, path: path, sqliteSetup: testSetup, maxReaders: 3);
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

    test('Insert Performance 3', () async {
      final db = PowerSyncDatabase(
          schema: pschema, path: path, sqliteSetup: testSetup, maxReaders: 3);
      await db.initialize();
      final timer = Stopwatch()..start();

      final con = db.connectionFactory().openConnection(updates: db.updates)
          as SqliteConnectionImpl;
      await con.inIsolateWriteTransaction((db) async {
        for (var i = 0; i < 1000; i++) {
          db.execute(
              'INSERT INTO customers(id, name, email) VALUES(uuid(), ?, ?)',
              ['Test User', 'user@example.org']);
        }
      });

      print("Completed synchronous inserts in ${timer.elapsed}");
      expect(await db.get('SELECT count(*) as count FROM customers'),
          equals({'count': 1000}));
    });

    test('Insert Performance 3b', () async {
      final db = PowerSyncDatabase(
          schema: pschema, path: path, sqliteSetup: testSetup, maxReaders: 3);
      await db.initialize();
      final timer = Stopwatch()..start();

      final con = db.connectionFactory().openConnection(updates: db.updates)
          as SqliteConnectionImpl;
      await con.inIsolateWriteTransaction((db) async {
        var stmt = db.prepare(
            'INSERT INTO customers(id, name, email) VALUES(uuid(), ?, ?)');
        for (var i = 0; i < 1000; i++) {
          stmt.execute(['Test User', 'user@example.org']);
        }
        stmt.dispose();
      });

      print("Completed synchronous inserts prepared in ${timer.elapsed}");
      expect(await db.get('SELECT count(*) as count FROM customers'),
          equals({'count': 1000}));
    });

    test('Insert Performance 4', () async {
      final db = PowerSyncDatabase(
          schema: pschema, path: path, sqliteSetup: testSetup, maxReaders: 3);
      await db.initialize();
      final timer = Stopwatch()..start();

      await db.writeTransaction((tx) async {
        // Not safe yet!
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
  });
}
