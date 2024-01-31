import 'package:powersync/powersync.dart';
import 'package:test/test.dart';

import 'util.dart';

const testId = "2290de4f-0488-4e50-abed-f8e8eb1d0b42";
final schema = Schema([
  Table('assets', [
    Column.text('created_at'),
    Column.text('make'),
    Column.text('model'),
    Column.text('serial_number'),
    Column.integer('quantity'),
    Column.text('user_id'),
    Column.real('weight'),
    Column.text('description'),
  ], indexes: [
    Index('makemodel', [IndexedColumn('make'), IndexedColumn('model')])
  ]),
  Table('customers', [Column.text('name'), Column.text('email')]),
  Table.insertOnly('logs', [Column.text('level'), Column.text('content')]),
  Table.localOnly('credentials', [Column.text('key'), Column.text('value')]),
  Table('aliased', [Column.text('name')], viewName: 'test1')
]);

void main() {
  group('Schema Tests', () {
    late String path;

    setUp(() async {
      path = dbPath();
      await cleanDb(path: path);
    });

    test('Schema versioning', () async {
      // Test that powersync_replace_schema() is a no-op when the schema is not
      // modified.

      final powersync = await setupPowerSync(path: path, schema: schema);

      final versionBefore = await powersync.get('PRAGMA schema_version');
      await powersync.updateSchema(schema);
      final versionAfter = await powersync.get('PRAGMA schema_version');

      // No change
      expect(versionAfter['schema_version'],
          equals(versionBefore['schema_version']));

      final schema2 = Schema([
        Table('assets', [
          Column.text('created_at'),
          Column.text('make'),
          Column.text('model'),
          Column.text('serial_number'),
          Column.integer('quantity'),
          Column.text('user_id'),
          Column.real('weights'),
          Column.text('description'),
        ], indexes: [
          Index('makemodel', [IndexedColumn('make'), IndexedColumn('model')])
        ]),
        Table('customers', [Column.text('name'), Column.text('email')]),
        Table.insertOnly(
            'logs', [Column.text('level'), Column.text('content')]),
        Table.localOnly(
            'credentials', [Column.text('key'), Column.text('value')]),
        Table('aliased', [Column.text('name')], viewName: 'test1')
      ]);

      await powersync.updateSchema(schema2);

      final versionAfter2 = await powersync.get('PRAGMA schema_version');

      // Updated
      expect(versionAfter2['schema_version'],
          greaterThan(versionAfter['schema_version']));

      final schema3 = Schema([
        Table('assets', [
          Column.text('created_at'),
          Column.text('make'),
          Column.text('model'),
          Column.text('serial_number'),
          Column.integer('quantity'),
          Column.text('user_id'),
          Column.real('weights'),
          Column.text('description'),
        ], indexes: [
          Index('makemodel',
              [IndexedColumn('make'), IndexedColumn.descending('model')])
        ]),
        Table('customers', [Column.text('name'), Column.text('email')]),
        Table.insertOnly(
            'logs', [Column.text('level'), Column.text('content')]),
        Table.localOnly(
            'credentials', [Column.text('key'), Column.text('value')]),
        Table('aliased', [Column.text('name')], viewName: 'test1')
      ]);

      await powersync.updateSchema(schema3);

      final versionAfter3 = await powersync.get('PRAGMA schema_version');

      // Updated again (index)
      expect(versionAfter3['schema_version'],
          greaterThan(versionAfter2['schema_version']));
    });

    test('Indexing', () async {
      final powersync = await setupPowerSync(path: path, schema: schema);

      final results = await powersync.execute(
          'EXPLAIN QUERY PLAN SELECT * FROM assets WHERE make = ?', ['test']);

      expect(results[0]['detail'],
          contains('USING INDEX ps_data__assets__makemodel'));

      // Now drop the index
      final schema2 = Schema([
        Table('assets', [
          Column.text('created_at'),
          Column.text('make'),
          Column.text('model'),
          Column.text('serial_number'),
          Column.integer('quantity'),
          Column.text('user_id'),
          Column.real('weight'),
          Column.text('description'),
        ], indexes: []),
      ]);
      await powersync.updateSchema(schema2);

      // Execute instead of getAll so that we don't get a cached query plan
      // from a different connection
      final results2 = await powersync.execute(
          'EXPLAIN QUERY PLAN SELECT * FROM assets WHERE make = ?', ['test']);

      expect(results2[0]['detail'], contains('SCAN'));
    });
  });
}
