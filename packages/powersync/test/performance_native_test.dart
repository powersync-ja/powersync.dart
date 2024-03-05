@TestOn('!browser')
import 'package:powersync/powersync.dart';
import 'package:test/test.dart';

import 'performance_shared_test.dart';
import 'utils/test_utils_impl.dart';

final testUtils = TestUtils();

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
    test('Insert Performance 3a - computeWithDatabase', () async {
      final db = PowerSyncDatabase.withFactory(
          await testUtils.testFactory(path: path),
          schema: pschema);
      await db.initialize();
      final timer = Stopwatch()..start();

      await db.computeWithDatabase((db) async {
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

    test('Insert Performance 3b - prepared statement', () async {
      final db = PowerSyncDatabase.withFactory(
          await testUtils.testFactory(path: path),
          schema: pschema);
      await db.initialize();
      final timer = Stopwatch()..start();

      await db.computeWithDatabase((db) async {
        var stmt = db.prepare(
            'INSERT INTO customers(id, name, email) VALUES(uuid(), ?, ?)');
        try {
          for (var i = 0; i < 1000; i++) {
            stmt.execute(['Test User', 'user@example.org']);
          }
        } finally {
          stmt.dispose();
        }
      });

      print("Completed synchronous inserts prepared in ${timer.elapsed}");
      expect(await db.get('SELECT count(*) as count FROM customers'),
          equals({'count': 1000}));
    });

    test('Insert Performance 3c - prepared statement, dart-generated ids',
        () async {
      final db = PowerSyncDatabase.withFactory(
          await testUtils.testFactory(path: path),
          schema: pschema);
      await db.initialize();
      // Test to exclude the function overhead time of generating uuids
      final timer = Stopwatch()..start();

      await db.computeWithDatabase((db) async {
        var ids = List.generate(1000, (index) => uuid.v4());
        var stmt = db
            .prepare('INSERT INTO customers(id, name, email) VALUES(?, ?, ?)');
        try {
          for (var id in ids) {
            stmt.execute([id, 'Test User', 'user@example.org']);
          }
        } finally {
          stmt.dispose();
        }
      });

      print("Completed synchronous inserts prepared in ${timer.elapsed}");
      expect(await db.get('SELECT count(*) as count FROM customers'),
          equals({'count': 1000}));
    });
    test('Insert Performance 3d - prepared statement, pre-generated ids',
        () async {
      final db = PowerSyncDatabase.withFactory(
          await testUtils.testFactory(path: path),
          schema: pschema);
      await db.initialize();
      // Test to completely exclude time taken to generate uuids
      var ids = List.generate(1000, (index) => uuid.v4());

      final timer = Stopwatch()..start();

      await db.computeWithDatabase((db) async {
        var stmt = db
            .prepare('INSERT INTO customers(id, name, email) VALUES(?, ?, ?)');
        for (var id in ids) {
          stmt.execute([id, 'Test User', 'user@example.org']);
        }
        stmt.dispose();
      });

      print("Completed synchronous inserts prepared in ${timer.elapsed}");
      expect(await db.get('SELECT count(*) as count FROM customers'),
          equals({'count': 1000}));
    });
  });
}
