import 'package:powersync/powersync.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;
import 'package:test/test.dart';

import 'util.dart';

const testId = "2290de4f-0488-4e50-abed-f8e8eb1d0b42";

void main() {
  setupLogger();

  group('CRUD Tests', () {
    late PowerSyncDatabase powersync;
    late String path;

    setUp(() async {
      path = dbPath();
      await cleanDb(path: path);

      powersync = await setupPowerSync(path: path);
    });

    test('INSERT', () async {
      expect(await powersync.getAll('SELECT * FROM ps_crud'), equals([]));
      await powersync.execute(
          'INSERT INTO assets(id, description) VALUES(?, ?)', [testId, 'test']);

      expect(
          await powersync.getAll('SELECT data FROM ps_crud ORDER BY id'),
          equals([
            {
              'data':
                  '{"op":"PUT","type":"assets","id":"$testId","data":{"description":"test"}}'
            }
          ]));

      await powersync.execute('DELETE FROM ps_crud WHERE 1');
    });

    test('INSERT OR REPLACE', () async {
      await powersync.execute(
          'INSERT INTO assets(id, description) VALUES(?, ?)', [testId, 'test']);
      await powersync.execute('DELETE FROM ps_crud WHERE 1');

      // Replace
      await powersync.execute(
          'INSERT OR REPLACE INTO assets(id, description) VALUES(?, ?)',
          [testId, 'test2']);

      // This generates another PUT
      expect(
          await powersync.getAll('SELECT data FROM ps_crud ORDER BY id'),
          equals([
            {
              'data':
                  '{"op":"PUT","type":"assets","id":"$testId","data":{"description":"test2"}}'
            }
          ]));

      expect(await powersync.get('SELECT count(*) AS count FROM assets'),
          equals({'count': 1}));

      // Make sure uniqueness is enforced
      expect(() async {
        await powersync.execute(
            'INSERT INTO assets(id, description) VALUES(?, ?)',
            [testId, 'test3']);
      },
          throwsA((e) =>
              e is sqlite.SqliteException &&
              e.message.contains('UNIQUE constraint failed')));
    });

    test('UPDATE', () async {
      await powersync.execute(
          'INSERT INTO assets(id, description, make) VALUES(?, ?, ?)',
          [testId, 'test', 'test']);
      await powersync.execute('DELETE FROM ps_crud WHERE 1');

      await powersync.execute(
          'UPDATE assets SET description = ? WHERE id = ?', ['test2', testId]);

      expect(
          await powersync.getAll('SELECT data FROM ps_crud ORDER BY id'),
          equals([
            {
              'data':
                  '{"op":"PATCH","type":"assets","id":"$testId","data":{"description":"test2"}}'
            }
          ]));
    });

    test('DELETE', () async {
      await powersync.execute(
          'INSERT INTO assets(id, description, make) VALUES(?, ?, ?)',
          [testId, 'test', 'test']);
      await powersync.execute('DELETE FROM ps_crud WHERE 1');

      await powersync.execute('DELETE FROM assets WHERE id = ?', [testId]);

      expect(
          await powersync.getAll('SELECT data FROM ps_crud ORDER BY id'),
          equals([
            {'data': '{"op":"DELETE","type":"assets","id":"$testId"}'}
          ]));
    });

    test('UPSERT not supported', () async {
      // Just shows that we cannot currently do this
      expect(() async {
        await powersync.execute(
            'INSERT INTO assets(id, description) VALUES(?, ?) ON CONFLICT DO UPDATE SET description = ?',
            [testId, 'test2', 'test3']);
      },
          throwsA((e) =>
              e is sqlite.SqliteException &&
              e.message.contains('cannot UPSERT a view')));
    });

    test('INSERT-only tables', () async {
      await powersync.disconnectedAndClear();
      powersync = await setupPowerSync(
          path: path,
          schema: const Schema([
            Table.insertOnly(
                'logs', [Column.text('level'), Column.text('content')])
          ]));
      expect(await powersync.getAll('SELECT * FROM ps_crud'), equals([]));
      await powersync.execute(
          'INSERT INTO logs(id, level, content) VALUES(?, ?, ?)',
          [testId, 'INFO', 'test log']);

      expect(
          await powersync.getAll('SELECT data FROM ps_crud ORDER BY id'),
          equals([
            {
              'data':
                  '{"op":"PUT","type":"logs","id":"$testId","data":{"level":"INFO","content":"test log"}}'
            }
          ]));

      expect(await powersync.getAll('SELECT * FROM logs'), equals([]));
    });

    test('big numbers - integer', () async {
      const bigNumber = 1 << 62;
      await powersync.execute(
          'INSERT INTO assets(id, quantity) VALUES(?, ?)', [testId, bigNumber]);

      expect(
          await powersync
              .get('SELECT quantity FROM assets WHERE id = ?', [testId]),
          equals({'quantity': bigNumber}));
      expect(
          await powersync.getAll('SELECT data FROM ps_crud ORDER BY id'),
          equals([
            {
              'data':
                  '{"op":"PUT","type":"assets","id":"$testId","data":{"quantity":$bigNumber}}'
            }
          ]));

      await powersync.execute('DELETE FROM ps_crud WHERE 1');
    });

    test('big numbers - text', () async {
      const bigNumber = 1 << 62;
      await powersync.execute('INSERT INTO assets(id, quantity) VALUES(?, ?)',
          [testId, '$bigNumber']);

      // Cast as INTEGER when querying
      expect(
          await powersync
              .get('SELECT quantity FROM assets WHERE id = ?', [testId]),
          equals({'quantity': bigNumber}));

      // Not cast as part of crud / persistance
      expect(
          await powersync.getAll('SELECT data FROM ps_crud ORDER BY id'),
          equals([
            {
              'data':
                  '{"op":"PUT","type":"assets","id":"$testId","data":{"quantity":"$bigNumber"}}'
            }
          ]));

      await powersync.execute('DELETE FROM ps_crud WHERE 1');

      await powersync.execute(
          'UPDATE assets SET description = ?, quantity = quantity + 1 WHERE id = ?',
          ['updated', testId]);

      expect(
          await powersync.getAll('SELECT data FROM ps_crud ORDER BY id'),
          equals([
            {
              'data':
                  '{"op":"PATCH","type":"assets","id":"$testId","data":{"quantity":${bigNumber + 1},"description":"updated"}}'
            }
          ]));
    });
  });
}
