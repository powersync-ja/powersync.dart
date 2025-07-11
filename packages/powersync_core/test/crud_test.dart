import 'package:powersync_core/powersync_core.dart';
import 'package:sqlite_async/sqlite3_common.dart';
import 'package:test/test.dart';

import 'utils/test_utils_impl.dart';

final testUtils = TestUtils();
const testId = "2290de4f-0488-4e50-abed-f8e8eb1d0b42";

void main() {
  group('CRUD Tests', () {
    late PowerSyncDatabase powersync;
    late String path;

    setUp(() async {
      path = testUtils.dbPath();
      await testUtils.cleanDb(path: path);

      powersync = await testUtils.setupPowerSync(path: path);
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
                  '{"op":"PUT","id":"$testId","type":"assets","data":{"description":"test"}}'
            }
          ]));

      var tx = (await powersync.getNextCrudTransaction())!;
      expect(tx.transactionId, equals(1));
      expect(
          tx.crud,
          equals([
            CrudEntry(
                1, UpdateType.put, 'assets', testId, 1, {"description": "test"})
          ]));
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
                  '{"op":"PUT","id":"$testId","type":"assets","data":{"description":"test2"}}'
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
          throwsA((dynamic e) =>
              e is SqliteException &&
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
                  '{"op":"PATCH","id":"$testId","type":"assets","data":{"description":"test2"}}'
            }
          ]));

      var tx = (await powersync.getNextCrudTransaction())!;
      expect(tx.transactionId, equals(2));
      expect(
          tx.crud,
          equals([
            CrudEntry(2, UpdateType.patch, 'assets', testId, 2,
                {"description": "test2"})
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
            {'data': '{"op":"DELETE","id":"$testId","type":"assets"}'}
          ]));

      var tx = (await powersync.getNextCrudTransaction())!;
      expect(tx.transactionId, equals(2));
      expect(tx.crud,
          equals([CrudEntry(2, UpdateType.delete, 'assets', testId, 2, null)]));
    });

    test('UPSERT not supported', () async {
      // Just shows that we cannot currently do this
      expect(() async {
        await powersync.execute(
            'INSERT INTO assets(id, description) VALUES(?, ?) ON CONFLICT DO UPDATE SET description = ?',
            [testId, 'test2', 'test3']);
      },
          throwsA((dynamic e) =>
              e is SqliteException &&
              e.message.contains('cannot UPSERT a view')));
    });

    test('INSERT-only tables', () async {
      await powersync.disconnectAndClear();
      await powersync.close();
      powersync = await testUtils.setupPowerSync(
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
          await powersync.getAll(
              "SELECT json_extract(data, '\$.id') as id FROM ps_crud ORDER BY id"),
          equals([
            {'id': testId}
          ]));

      expect(await powersync.getAll('SELECT * FROM logs'), equals([]));

      var tx = (await powersync.getNextCrudTransaction())!;
      expect(tx.transactionId, equals(1));
      expect(
          tx.crud,
          equals([
            CrudEntry(1, UpdateType.put, 'logs', testId, 1,
                {"level": "INFO", "content": "test log"})
          ]));
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
          await powersync.getAll(
              "SELECT json_extract(data, '\$.id') as id FROM ps_crud ORDER BY id"),
          equals([
            {"id": testId}
          ]));

      var tx = (await powersync.getNextCrudTransaction())!;
      expect(tx.transactionId, equals(1));
      expect(
          tx.crud,
          equals([
            CrudEntry(
                1, UpdateType.put, 'assets', testId, 1, {"quantity": bigNumber})
          ]));
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
                  '{"op":"PUT","id":"$testId","type":"assets","data":{"quantity":"$bigNumber"}}'
            }
          ]));

      await powersync.execute('DELETE FROM ps_crud WHERE 1');

      await powersync.execute(
          'UPDATE assets SET quantity = quantity + 1 WHERE id = ?', [testId]);

      expect(
          await powersync.getAll('SELECT data FROM ps_crud ORDER BY id'),
          equals([
            {
              'data':
                  '{"op":"PATCH","id":"$testId","type":"assets","data":{"quantity":${bigNumber + 1}}}'
            }
          ]));
    });

    test('Transaction grouping', () async {
      expect(await powersync.getAll('SELECT * FROM ps_crud'), equals([]));
      await powersync.writeTransaction((tx) async {
        await tx.execute('INSERT INTO assets(id, description) VALUES(?, ?)',
            [testId, 'test1']);
        await tx.execute('INSERT INTO assets(id, description) VALUES(?, ?)',
            ['test2', 'test2']);
      });

      await powersync.writeTransaction((tx) async {
        await tx.execute('UPDATE assets SET description = ? WHERE id = ?',
            ['updated', testId]);
      });

      var tx1 = (await powersync.getNextCrudTransaction())!;

      expect(tx1.transactionId, equals(1));
      expect(
          tx1.crud,
          equals([
            CrudEntry(1, UpdateType.put, 'assets', testId, 1,
                {"description": "test1"}),
            CrudEntry(2, UpdateType.put, 'assets', 'test2', 1,
                {"description": "test2"})
          ]));
      await tx1.complete();

      var tx2 = (await powersync.getNextCrudTransaction())!;
      expect(tx2.transactionId, equals(2));
      expect(
          tx2.crud,
          equals([
            CrudEntry(3, UpdateType.patch, 'assets', testId, 2,
                {"description": "updated"}),
          ]));
      await tx2.complete();
      expect(await powersync.getNextCrudTransaction(), equals(null));
    });

    test('include metadata', () async {
      await powersync.updateSchema(Schema([
        Table(
          'lists',
          [Column.text('name')],
          trackMetadata: true,
        )
      ]));

      await powersync.execute(
          'INSERT INTO lists (id, name, _metadata) VALUES (uuid(), ?, ?)',
          ['entry', 'so meta']);

      final batch = await powersync.getNextCrudTransaction();
      expect(batch!.crud[0].metadata, 'so meta');
    });

    test('include old values', () async {
      await powersync.updateSchema(Schema([
        Table(
          'lists',
          [Column.text('name'), Column.text('content')],
          trackPreviousValues: TrackPreviousValuesOptions(),
        )
      ]));

      await powersync.execute(
          'INSERT INTO lists (id, name, content) VALUES (uuid(), ?, ?)',
          ['entry', 'content']);
      await powersync.execute('DELETE FROM ps_crud;');
      await powersync.execute('UPDATE lists SET name = ?;', ['new name']);

      final batch = await powersync.getNextCrudTransaction();
      expect(batch!.crud[0].previousValues,
          {'name': 'entry', 'content': 'content'});
    });

    test('include old values with column filter', () async {
      await powersync.updateSchema(Schema([
        Table(
          'lists',
          [Column.text('name'), Column.text('content')],
          trackPreviousValues:
              TrackPreviousValuesOptions(columnFilter: ['name']),
        )
      ]));

      await powersync.execute(
          'INSERT INTO lists (id, name, content) VALUES (uuid(), ?, ?)',
          ['name', 'content']);
      await powersync.execute('DELETE FROM ps_crud;');
      await powersync.execute('UPDATE lists SET name = ?, content = ?',
          ['new name', 'new content']);

      final batch = await powersync.getNextCrudTransaction();
      expect(batch!.crud[0].previousValues, {'name': 'name'});
    });

    test('include old values when changed', () async {
      await powersync.updateSchema(Schema([
        Table(
          'lists',
          [Column.text('name'), Column.text('content')],
          trackPreviousValues:
              TrackPreviousValuesOptions(onlyWhenChanged: true),
        )
      ]));

      await powersync.execute(
          'INSERT INTO lists (id, name, content) VALUES (uuid(), ?, ?)',
          ['name', 'content']);
      await powersync.execute('DELETE FROM ps_crud;');
      await powersync.execute('UPDATE lists SET name = ?', ['new name']);

      final batch = await powersync.getNextCrudTransaction();
      expect(batch!.crud[0].previousValues, {'name': 'name'});
    });

    test('ignore empty update', () async {
      await powersync.updateSchema(Schema([
        Table(
          'lists',
          [Column.text('name')],
          ignoreEmptyUpdates: true,
        )
      ]));

      await powersync
          .execute('INSERT INTO lists (id, name) VALUES (uuid(), ?)', ['name']);
      await powersync.execute('DELETE FROM ps_crud;');
      await powersync.execute('UPDATE lists SET name = ?;', ['name']);
      expect(await powersync.getNextCrudTransaction(), isNull);
    });
  });
}
