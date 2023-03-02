import 'dart:math';

import 'package:powersync/powersync.dart';
import 'package:powersync/src/background_database.dart';
import 'package:test/test.dart';

import 'util.dart';

void main() {
  setupLogger();

  group('Basic Tests', () {
    late String path;

    setUp(() async {
      path = dbPath();
      await cleanDb(path: path);
    });

    tearDown(() async {
      await cleanDb(path: path);
    });

    test('Basic Setup', () async {
      final db = await setupPowerSync(path: path);
      await db.execute(
          'INSERT INTO assets(id, make) VALUES(uuid(), ?)', ['Test Make']);
      final result = await db.get('SELECT make FROM assets');
      expect(result, equals({'make': 'Test Make'}));
      expect(
          await db.execute('PRAGMA journal_mode'),
          equals([
            {'journal_mode': 'wal'}
          ]));
      expect(
          await db.execute('PRAGMA locking_mode'),
          equals([
            {'locking_mode': 'normal'}
          ]));
    });

    test('Concurrency', () async {
//       var q = """WITH RECURSIVE r(i) AS (
//   VALUES(0)
//   UNION ALL
//   SELECT i FROM r
//   LIMIT 1000000
// )
// SELECT i FROM r WHERE i = 1""";
      final db = PowerSyncDatabase(
          schema: schema, path: path, sqliteSetup: testSetup, maxReaders: 3);
      await db.initialize();

      print("${DateTime.now()} start");
      var futures = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11].map((i) => db.get(
          'SELECT ? as i, powersync_sleep(?) as sleep, powersync_connection_name() as connection',
          [i, 5 + Random().nextInt(10)]));
      await for (var result in Stream.fromFutures(futures)) {
        print("${DateTime.now()} $result");
      }
    });

    test('Insert Performance 1', () async {
      final db = PowerSyncDatabase(
          schema: schema, path: path, sqliteSetup: testSetup, maxReaders: 3);
      await db.initialize();
      await db.execute(
          'CREATE TABLE data(id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT, email TEXT)');
      final timer = Stopwatch()..start();

      for (var i = 0; i < 1000; i++) {
        await db.execute('INSERT INTO data(name, email) VALUES(?, ?)',
            ['Test User', 'user@example.org']);
      }
      print("Completed sequential inserts in ${timer.elapsed}");
      expect(await db.get('SELECT count(*) as count FROM data'),
          equals({'count': 1000}));
    });

    test('Insert Performance 2', () async {
      final db = PowerSyncDatabase(
          schema: schema, path: path, sqliteSetup: testSetup, maxReaders: 3);
      await db.initialize();
      await db.execute(
          'CREATE TABLE data(id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT, email TEXT)');
      final timer = Stopwatch()..start();

      await db.writeTransaction((tx) async {
        for (var i = 0; i < 1000; i++) {
          await tx.execute('INSERT INTO data(name, email) VALUES(?, ?)',
              ['Test User', 'user@example.org']);
        }
      });
      print("Completed transaction inserts in ${timer.elapsed}");
      expect(await db.get('SELECT count(*) as count FROM data'),
          equals({'count': 1000}));
    });

    test('Insert Performance 3', () async {
      final db = PowerSyncDatabase(
          schema: schema, path: path, sqliteSetup: testSetup, maxReaders: 3);
      await db.initialize();
      await db.execute(
          'CREATE TABLE data(id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT, email TEXT)');
      final timer = Stopwatch()..start();

      final con = db.connectionFactory().openConnection(updates: db.updates)
          as SqliteConnectionImpl;
      await con.inIsolateWriteTransaction((db) async {
        for (var i = 0; i < 1000; i++) {
          db.execute('INSERT INTO data(name, email) VALUES(?, ?)',
              ['Test User', 'user@example.org']);
        }
      });

      print("Completed synchronous inserts in ${timer.elapsed}");
      expect(await db.get('SELECT count(*) as count FROM data'),
          equals({'count': 1000}));
    });

    test('Insert Performance 3b', () async {
      final db = PowerSyncDatabase(
          schema: schema, path: path, sqliteSetup: testSetup, maxReaders: 3);
      await db.initialize();
      await db.execute(
          'CREATE TABLE data(id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT, email TEXT)');
      final timer = Stopwatch()..start();

      final con = db.connectionFactory().openConnection(updates: db.updates)
          as SqliteConnectionImpl;
      await con.inIsolateWriteTransaction((db) async {
        var stmt = db.prepare('INSERT INTO data(name, email) VALUES(?, ?)');
        for (var i = 0; i < 1000; i++) {
          stmt.execute(['Test User', 'user@example.org']);
        }
        stmt.dispose();
      });

      print("Completed synchronous inserts prepared in ${timer.elapsed}");
      expect(await db.get('SELECT count(*) as count FROM data'),
          equals({'count': 1000}));
    });

    test('Insert Performance 4', () async {
      final db = PowerSyncDatabase(
          schema: schema, path: path, sqliteSetup: testSetup, maxReaders: 3);
      await db.initialize();
      await db.execute(
          'CREATE TABLE data(id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT, email TEXT)');
      final timer = Stopwatch()..start();

      await db.writeTransaction((tx) async {
        // Not safe yet!
        List<Future> futures = [];
        for (var i = 0; i < 1000; i++) {
          var future = tx.execute('INSERT INTO data(name, email) VALUES(?, ?)',
              ['Test User', 'user@example.org']);
          futures.add(future);
        }
        await Future.wait(futures);
      });
      print("Completed pipelined inserts in ${timer.elapsed}");
      expect(await db.get('SELECT count(*) as count FROM data'),
          equals({'count': 1000}));
    });
  });
}
