import 'dart:math';

import 'package:powersync/powersync.dart';
import 'package:test/test.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;
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

    // Manual test
    test('Concurrency', () async {
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

    test('read-only transactions', () async {
      final db = await setupPowerSync(path: path);

      // Can read
      await db.getAll("WITH test AS (SELECT 1 AS one) SELECT * FROM test");

      // Cannot write
      await expectLater(() async {
        await db.getAll('INSERT INTO assets(id) VALUES(uuid())');
      },
          throwsA((e) =>
              e is sqlite.SqliteException &&
              e.message
                  .contains('attempt to write in a read-only transaction')));

      // Can use WITH ... SELECT
      await db.getAll("WITH test AS (SELECT 1 AS one) SELECT * FROM test");

      // Cannot use WITH .... INSERT
      await expectLater(() async {
        await db.getAll(
            "WITH test AS (SELECT 1 AS one) INSERT INTO assets(id) SELECT one FROM test");
      },
          throwsA((e) =>
              e is sqlite.SqliteException &&
              e.message
                  .contains('attempt to write in a read-only transaction')));

      await db.writeTransaction((tx) async {
        // Within a write transaction, this is fine
        await tx.getAll('INSERT INTO assets(id) VALUES(uuid()) RETURNING *');
      });
    });

    test('should not allow direct db calls within a transaction callback',
        () async {
      final db = await setupPowerSync(path: path);

      await db.writeTransaction((tx) async {
        await expectLater(() async {
          await db.execute('INSERT INTO assets(id) VALUES(uuid())');
        }, throwsA((e) => e is AssertionError));
      });
    });

    test('does allow read-only db calls within transaction callback', () async {
      final db = await setupPowerSync(path: path);

      await db.writeTransaction((tx) async {
        // This uses a different connection, so it's fine.
        // Perhaps we should warn on this, since it's likely unintentional?
        await db.getAll('SELECT * FROM assets');
      });

      await db.readTransaction((tx) async {
        // This does actually attempt a lock on the same connection, so it
        // errors.
        // This also exposes an interesting test case where the read transaction
        // opens another connection, but doesn't use it.
        await expectLater(() async {
          await db.getAll('SELECT * FROM assets');
        }, throwsA((e) => e is AssertionError));
      });
    });

    test('does allow read-only db calls within lock callback', () async {
      final db = await setupPowerSync(path: path);
      // Locks - should behave the same as transactions above

      await db.writeLock((tx) async {
        await db.getAll('SELECT * FROM assets');
      });

      await db.readLock((tx) async {
        await expectLater(() async {
          await db.getAll('SELECT * FROM assets');
        }, throwsA((e) => e is AssertionError));
      });
    });

    test('should allow PRAMGAs', () async {
      final db = await setupPowerSync(path: path);
      // Not allowed in transactions, but does work as a direct statement.
      await db.execute('PRAGMA wal_checkpoint(TRUNCATE)');
      await db.execute('VACUUM');
    });
  });
}
