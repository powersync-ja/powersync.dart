@TestOn('!browser')
library;

import 'dart:async';
import 'dart:math';

import 'package:powersync_core/powersync_core.dart';
import 'package:sqlite_async/sqlite3_common.dart';
import 'package:test/test.dart';
import 'utils/abstract_test_utils.dart';
import 'utils/test_utils_impl.dart';

final testUtils = TestUtils();

void main() {
  group('Basic Tests', () {
    late String path;

    setUp(() async {
      path = testUtils.dbPath();
      await testUtils.cleanDb(path: path);
    });

    tearDown(() async {
      await testUtils.cleanDb(path: path);
    });

    test('Basic Setup', () async {
      final db = await testUtils.setupPowerSync(path: path);
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
      final db = PowerSyncDatabase.withFactory(
          await testUtils.testFactory(path: path),
          schema: defaultSchema,
          maxReaders: 3);
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
      final db = await testUtils.setupPowerSync(path: path);

      // Can read
      await db.getAll("WITH test AS (SELECT 1 AS one) SELECT * FROM test");

      // Cannot write
      await expectLater(() async {
        await db.getAll('INSERT INTO assets(id) VALUES(?)', ['test']);
      },
          throwsA((dynamic e) =>
              e is SqliteException &&
              e.message
                  .contains('attempt to write in a read-only transaction')));

      // Can use WITH ... SELECT
      await db.getAll("WITH test AS (SELECT 1 AS one) SELECT * FROM test");

      // Cannot use WITH .... INSERT
      await expectLater(() async {
        await db.getAll(
            "WITH test AS (SELECT 1 AS one) INSERT INTO assets(id) SELECT one FROM test");
      },
          throwsA((dynamic e) =>
              e is SqliteException &&
              e.message
                  .contains('attempt to write in a read-only transaction')));

      await db.writeTransaction((tx) async {
        // Within a write transaction, this is fine
        await tx
            .getAll('INSERT INTO assets(id) VALUES(?) RETURNING *', ['test']);
      });
    });

    test(
        'should allow read-only db calls within transaction callback in separate zone',
        () async {
      final db = await testUtils.setupPowerSync(path: path);

      // Get a reference to the parent zone (outside the transaction).
      final zone = Zone.current;

      // Each of these are fine, since it could use a separate connection.
      // Note: In highly concurrent cases, it could exhaust the connection pool and cause a deadlock.

      await db.writeTransaction((tx) async {
        // Use the parent zone to avoid the "recursive lock" error.
        await zone.fork().run(() async {
          await db.getAll('SELECT * FROM assets');
        });
      });

      await db.readTransaction((tx) async {
        await zone.fork().run(() async {
          await db.getAll('SELECT * FROM assets');
        });
      });

      await db.readTransaction((tx) async {
        await zone.fork().run(() async {
          await db.execute('SELECT * FROM assets');
        });
      });

      // Note: This would deadlock, since it shares a global write lock.
      // await db.writeTransaction((tx) async {
      //   await zone.fork().run(() async {
      //     await db.execute('SELECT * FROM test_data');
      //   });
      // });
    });
  });
}
