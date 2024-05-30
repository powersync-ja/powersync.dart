import 'package:sqlite_async/mutex.dart';
import 'package:test/test.dart';
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

    test('should not allow direct db calls within a transaction callback',
        () async {
      final db = await testUtils.setupPowerSync(path: path);

      await db.writeTransaction((tx) async {
        await expectLater(() async {
          await db.execute('INSERT INTO assets(id) VALUES(?)', ['test']);
        }, throwsA((e) => e is LockError && e.message.contains('tx.execute')));
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
        }, throwsA((e) => e is LockError && e.message.contains('tx.getAll')));
      });

      await db.readTransaction((tx) async {
        // This does actually attempt a lock on the same connection, so it
        // errors.
        // This also exposes an interesting test case where the read transaction
        // opens another connection, but doesn't use it.
        await expectLater(() async {
          await db.getAll('SELECT * FROM assets');
        }, throwsA((e) => e is LockError && e.message.contains('tx.getAll')));
      });
    });

    test('should not allow read-only db calls within lock callback', () async {
      final db = await testUtils.setupPowerSync(path: path);
      // Locks - should behave the same as transactions above

      await db.writeLock((tx) async {
        await expectLater(() async {
          await db.getOptional('SELECT * FROM assets');
        },
            throwsA(
                (e) => e is LockError && e.message.contains('tx.getOptional')));
      });

      await db.readLock((tx) async {
        await expectLater(() async {
          await db.getOptional('SELECT * FROM assets');
        },
            throwsA(
                (e) => e is LockError && e.message.contains('tx.getOptional')));
      });
    });

    test('should allow PRAMGAs', () async {
      final db = await testUtils.setupPowerSync(path: path);
      // Not allowed in transactions, but does work as a direct statement.
      await db.execute('PRAGMA wal_checkpoint(TRUNCATE)');
      await db.execute('VACUUM');
    });
  });
}
