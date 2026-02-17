import 'package:logging/logging.dart';
import 'package:powersync_core/powersync_core.dart';
import 'package:sqlite_async/mutex.dart';
import 'package:test/test.dart';
import 'package:uuid/parsing.dart';

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

    test('warns on duplicate database', () async {
      final logger = Logger.detached('powersync.test')..level = Level.WARNING;
      final events = <LogRecord>[];
      final subscription = logger.onRecord.listen(events.add);
      addTearDown(subscription.cancel);

      final firstInstance =
          await testUtils.setupPowerSync(path: path, logger: logger);
      await firstInstance.initialize();
      expect(events, isEmpty);

      final secondInstance =
          await testUtils.setupPowerSync(path: path, logger: logger);
      await secondInstance.initialize();
      expect(
        events,
        contains(
          isA<LogRecord>().having(
            (e) => e.message,
            'message',
            contains(
                'Multiple instances for the same database have been detected.'),
          ),
        ),
      );
    });

    test('should not allow direct db calls within a transaction callback',
        () async {
      final db = await testUtils.setupPowerSync(path: path);

      await db.writeTransaction((tx) async {
        await expectLater(() async {
          await db.execute('INSERT INTO assets(id) VALUES(?)', ['test']);
        },
            throwsA((dynamic e) =>
                e is LockError && e.message.contains('tx.execute')));
      });
    });

    test('should not allow read-only db calls within transaction callback',
        () async {
      final db = await testUtils.setupPowerSync(path: path);

      await db.writeTransaction((tx) async {
        // This uses a different connection, so it _could_ work.
        // But it's likely unintentional and could cause weird bugs, so we don't
        // allow it by default.
        await expectLater(() async {
          await db.getAll('SELECT * FROM assets');
        },
            throwsA((dynamic e) =>
                e is LockError && e.message.contains('tx.getAll')));
      });

      await db.readTransaction((tx) async {
        // This does actually attempt a lock on the same connection, so it
        // errors.
        // This also exposes an interesting test case where the read transaction
        // opens another connection, but doesn't use it.
        await expectLater(() async {
          await db.getAll('SELECT * FROM assets');
        },
            throwsA((dynamic e) =>
                e is LockError && e.message.contains('tx.getAll')));
      });
    });

    test('should not allow read-only db calls within lock callback', () async {
      final db = await testUtils.setupPowerSync(path: path);
      // Locks - should behave the same as transactions above

      await db.writeLock((tx) async {
        await expectLater(() async {
          await db.getOptional('SELECT * FROM assets');
        },
            throwsA((dynamic e) =>
                e is LockError && e.message.contains('tx.getOptional')));
      });

      await db.readLock((tx) async {
        await expectLater(() async {
          await db.getOptional('SELECT * FROM assets');
        },
            throwsA((dynamic e) =>
                e is LockError && e.message.contains('tx.getOptional')));
      });
    });

    test('should allow PRAMGAs', () async {
      final db = await testUtils.setupPowerSync(path: path);
      // Not allowed in transactions, but does work as a direct statement.
      await db.execute('PRAGMA wal_checkpoint(TRUNCATE)');
      await db.execute('VACUUM');
    });

    test('should have a client id', () async {
      final db = await testUtils.setupPowerSync(path: path);

      final id = await db.getClientId();
      // Check that it is a valid uuid
      UuidParsing.parseAsByteList(id);
    });

    test('does not emit duplicate sync status events', () async {
      final db = await testUtils.setupPowerSync(path: path);
      expectLater(
        db.statusStream,
        emitsInOrder(
          [
            // Manual setStatus call. hasSynced set to true because lastSyncedAt is set
            isA<SyncStatus>().having((e) => e.hasSynced, 'hasSynced', true),
            // Closing the database emits a disconnected status
            isA<SyncStatus>().having((e) => e.connected, 'connected', false),
            emitsDone
          ],
        ),
      );

      final status = SyncStatus(connected: true, lastSyncedAt: DateTime.now());
      db.setStatus(status);
      db.setStatus(status); // Should not re-emit!

      await db.close();
    });

    test('can clear raw tables', () async {
      final db = await testUtils.setupPowerSync(path: path);
      await db.updateSchema(const Schema([], rawTables: [
        RawTable(
          name: 'unused',
          put: PendingStatement(sql: '', params: []),
          delete: PendingStatement(sql: '', params: []),
          clear: 'DELETE FROM lists',
        )
      ]));
      await db.execute(
          'CREATE TABLE lists (id TEXT NOT NULL PRIMARY KEY, name TEXT)');
      await db
          .execute('INSERT INTO lists (id, name) VALUES (uuid(), ?)', ['list']);

      expect(await db.getAll('SELECT * FROM lists'), hasLength(1));
      await db.disconnectAndClear();
      expect(await db.getAll('SELECT * FROM lists'), isEmpty);
    });
  });
}
