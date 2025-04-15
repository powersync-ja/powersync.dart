import 'package:powersync_core/powersync_core.dart';
import 'package:test/test.dart';

import 'utils/test_utils_impl.dart';

final testUtils = TestUtils();

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
      path = testUtils.dbPath();
      await testUtils.cleanDb(path: path);
    });

    test('Schema versioning', () async {
      // Test that powersync_replace_schema() is a no-op when the schema is not
      // modified.

      final powersync =
          await testUtils.setupPowerSync(path: path, schema: schema);

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
          greaterThan(versionAfter['schema_version'] as int));

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
          greaterThan(versionAfter2['schema_version'] as int));
    });

    /// The assets table is locked after performing the EXPLAIN QUERY
    test('Indexing', () async {
      final powersync =
          await testUtils.setupPowerSync(path: path, schema: schema);

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

    test('Validation runs on setup', () async {
      final schema = Schema([
        Table('#assets', [
          Column.text('name'),
        ]),
      ]);

      try {
        await testUtils.setupPowerSync(path: path, schema: schema);
      } catch (e) {
        expect(
            e,
            isA<AssertionError>().having((e) => e.message, 'message',
                'Invalid characters in table name: #assets'));
      }
    });

    test('Validation runs on update', () async {
      final schema = Schema([
        Table('works', [
          Column.text('name'),
        ]),
      ]);

      final powersync =
          await testUtils.setupPowerSync(path: path, schema: schema);

      final schema2 = Schema([
        Table('#notworking', [
          Column.text('created_at'),
        ]),
      ]);

      await expectLater(
        () => powersync.updateSchema(schema2),
        throwsA(isA<AssertionError>().having((e) => e.message, 'message',
            'Invalid characters in table name: #notworking')),
      );
    });
  });

  group('Table', () {
    test('Create a synced table', () {
      final table = Table('users', [
        Column('name', ColumnType.text),
        Column('age', ColumnType.integer),
      ]);

      expect(table.name, equals('users'));
      expect(table.columns.length, equals(2));
      expect(table.localOnly, isFalse);
      expect(table.insertOnly, isFalse);
      expect(table.internalName, equals('ps_data__users'));
      expect(table.viewName, equals('users'));
    });

    test('Create a local-only table', () {
      final table = Table.localOnly(
          'local_users',
          [
            Column('name', ColumnType.text),
          ],
          viewName: 'local_user_view');

      expect(table.name, equals('local_users'));
      expect(table.localOnly, isTrue);
      expect(table.insertOnly, isFalse);
      expect(table.internalName, equals('ps_data_local__local_users'));
      expect(table.viewName, equals('local_user_view'));
    });

    test('Create an insert-only table', () {
      final table = Table.insertOnly('logs', [
        Column('message', ColumnType.text),
        Column('timestamp', ColumnType.integer),
      ]);

      expect(table.name, equals('logs'));
      expect(table.localOnly, isFalse);
      expect(table.insertOnly, isTrue);
      expect(table.internalName, equals('ps_data__logs'));
      expect(table.indexes, isEmpty);
    });

    test('Access column by name', () {
      final table = Table('products', [
        Column('name', ColumnType.text),
        Column('price', ColumnType.real),
      ]);

      expect(table['name'].type, equals(ColumnType.text));
      expect(table['price'].type, equals(ColumnType.real));
      expect(() => table['nonexistent'], throwsStateError);
    });

    test('Validate table name', () {
      final invalidTableName =
          Table('#invalid_table_name', [Column('name', ColumnType.text)]);

      expect(
        () => invalidTableName.validate(),
        throwsA(
          isA<AssertionError>().having(
            (e) => e.message,
            'message',
            'Invalid characters in table name: #invalid_table_name',
          ),
        ),
      );
    });

    test('Validate view name', () {
      final invalidTableName = Table(
          'valid_table_name', [Column('name', ColumnType.text)],
          viewName: '#invalid_view_name');

      expect(
        () => invalidTableName.validate(),
        throwsA(
          isA<AssertionError>().having(
            (e) => e.message,
            'message',
            'Invalid characters in view name: #invalid_view_name',
          ),
        ),
      );
    });

    test('Validate table definition', () {
      final validTable = Table('valid_table', [
        Column('name', ColumnType.text),
        Column('age', ColumnType.integer),
      ]);

      expect(() => validTable.validate(), returnsNormally);
    });

    test('Table with id column', () {
      final invalidTable = Table('invalid_table', [
        Column('id', ColumnType.integer), // Duplicate 'id' column
        Column('name', ColumnType.text),
      ]);

      expect(
        () => invalidTable.validate(),
        throwsA(
          isA<AssertionError>().having(
            (e) => e.message,
            'message',
            'invalid_table: id column is automatically added, custom id columns are not supported',
          ),
        ),
      );
    });

    test('Table with too many columns', () {
      final List<Column> manyColumns = List.generate(
        2000, // Exceeds MAX_NUMBER_OF_COLUMNS
        (index) => Column('col$index', ColumnType.text),
      );

      final tableTooManyColumns = Table('too_many_columns', manyColumns);

      expect(
        () => tableTooManyColumns.validate(),
        throwsA(
          isA<AssertionError>().having(
            (e) => e.message,
            'message',
            'Table too_many_columns has more than 1999 columns, which is not supported',
          ),
        ),
      );
    });

    test('Schema without duplicate table names', () {
      final schema = Schema([
        Table('duplicate', [
          Column.text('name'),
        ]),
        Table('not_duplicate', [
          Column.text('name'),
        ]),
      ]);

      expect(() => schema.validate(), returnsNormally);
    });

    test('Schema with duplicate table names', () {
      final schema = Schema([
        Table('clone', [
          Column.text('name'),
        ]),
        Table('clone', [
          Column.text('name'),
        ]),
      ]);

      expect(
        () => schema.validate(),
        throwsA(
          isA<AssertionError>().having(
            (e) => e.message,
            'message',
            'Duplicate table name: clone',
          ),
        ),
      );
    });

    test('toJson method', () {
      final table = Table('users', [
        Column('name', ColumnType.text),
        Column('age', ColumnType.integer),
      ], indexes: [
        Index('name_index', [IndexedColumn('name')])
      ]);

      final json = table.toJson();

      expect(json['name'], equals('users'));
      expect(json['view_name'], isNull);
      expect(json['local_only'], isFalse);
      expect(json['insert_only'], isFalse);
      expect(json['columns'].length, equals(2));
      expect(json['indexes'].length, equals(1));
    });
  });
}
