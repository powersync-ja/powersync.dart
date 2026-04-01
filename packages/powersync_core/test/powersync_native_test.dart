@TestOn('!browser')
library;

import 'dart:async';

import 'package:powersync_core/powersync_core.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:sqlite_async/sqlite_async.dart';
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

    test('Concurrency', () async {
      final db = PowerSyncDatabase.withFactory(
        await testUtils.testFactory(
            path: path, options: SqliteOptions(maxReaders: 3)),
        schema: defaultSchema,
      );
      addTearDown(db.close);

      final hasConcurrentTransactions = Completer<void>();
      final releaseConnections = Completer<void>();
      var startedTransactions = 0;
      for (var i = 0; i < 3; i++) {
        final tx = db.readTransaction((tx) async {
          startedTransactions++;
          if (startedTransactions == 3) {
            hasConcurrentTransactions.complete();
          }

          await releaseConnections.future;
          expect(await tx.getAll('SELECT * FROM customers'), hasLength(0));
        });
        expectLater(tx, completes);
      }

      await hasConcurrentTransactions.future;

      // Ensure we can write while read transactions are active.
      await db.execute(
        'INSERT INTO customers (id, name, email) VALUES (uuid(), ?, ?)',
        ['name', 'email'],
      );
      releaseConnections.complete();
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
              e.message.contains('attempt to write a readonly database')));

      // Can use WITH ... SELECT
      await db.getAll("WITH test AS (SELECT 1 AS one) SELECT * FROM test");

      // Cannot use WITH .... INSERT
      await expectLater(() async {
        await db.getAll(
            "WITH test AS (SELECT 1 AS one) INSERT INTO assets(id) SELECT one FROM test");
      },
          throwsA((dynamic e) =>
              e is SqliteException &&
              e.message.contains('attempt to write a readonly database')));

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
