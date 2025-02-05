import 'dart:convert';

import 'package:powersync_core/powersync_core.dart';
import 'package:sqlite_async/src/utils/shared_utils.dart';
import 'package:test/test.dart';

import 'utils/test_utils_impl.dart';

final testUtils = TestUtils();

const assetId = "2290de4f-0488-4e50-abed-f8e8eb1d0b42";
const userId = "3390de4f-0488-4e50-abed-f8e8eb1d0b42";
const customerId = "4490de4f-0488-4e50-abed-f8e8eb1d0b42";

/// The schema contains two copies of each table - a local-only one, and
/// a online/synced one. Depending on the 'online' flag, one of those gets
/// the main 'assets' / 'customer' view name.
///
/// For online, we have these views:
///   assets
///   local_assets
///   customers
///   local_customers
///
/// For offline, the views become:
///   online_assets
///   assets
///   online_customers
///   customers
Schema makeSchema(bool online) {
  String onlineName(String table) {
    if (online) {
      return table;
    } else {
      return "online_$table";
    }
  }

  String localName(String table) {
    if (online) {
      return "local_$table";
    } else {
      return table;
    }
  }

  final tables = [
    Table('assets', [
      Column.text('created_at'),
      Column.text('make'),
      Column.text('model'),
      Column.text('serial_number'),
      Column.integer('quantity'),
      Column.text('user_id'),
      Column.text('customer_id'),
      Column.text('description'),
    ], indexes: [
      Index('makemodel', [IndexedColumn('make'), IndexedColumn('model')])
    ]),
    Table('customers', [Column.text('name'), Column.text('email')]),
  ];

  return Schema([
    for (var table in tables)
      Table(table.name, table.columns,
          indexes: table.indexes, viewName: onlineName(table.name)),
    for (var table in tables)
      Table.localOnly('local_${table.name}', table.columns,
          indexes: table.indexes, viewName: localName(table.name))
  ]);
}

void main() {
  group('Offline-online Tests', () {
    late String path;

    setUp(() async {
      path = testUtils.dbPath();
      await testUtils.cleanDb(path: path);
    });

    test('Switch from offline-only to online', () async {
      // Start with "offline-only" schema.
      // This does not record any operations to the crud queue.
      final db =
          await testUtils.setupPowerSync(path: path, schema: makeSchema(false));

      await db.execute('INSERT INTO customers(id, name, email) VALUES(?, ?, ?)',
          [customerId, 'test customer', 'test@example.org']);
      await db.execute(
          'INSERT INTO assets(id, description, customer_id) VALUES(?, ?, ?)',
          [assetId, 'test', customerId]);
      await db
          .execute('UPDATE assets SET description = description || ?', ['.']);

      expect(
          await db.getAll('SELECT data FROM ps_crud ORDER BY id'), equals([]));

      // Now switch to the "online" schema
      await db.updateSchema(makeSchema(true));

      // Note that updateSchema cannot be called inside a transaction, and there
      // is a possibility of crash between updating the schema, and when the data
      // has been moved. It may be best to attempt the data move on every application
      // start where the online schema is used, if there is any local_ data still present.

      await db.writeTransaction((tx) async {
        // Copy local data to the "online" views.
        // This records each operation to the crud queue.
        await tx.execute('INSERT INTO customers SELECT * FROM local_customers');
        await tx.execute(
            'INSERT INTO assets(id, description, customer_id, user_id) SELECT id, description, customer_id, ? FROM local_assets',
            [userId]);

        // Delete the "offline-only" data.
        await tx.execute('DELETE FROM local_customers');
        await tx.execute('DELETE FROM local_assets');
      });

      final crud = (await db.getAll('SELECT data FROM ps_crud ORDER BY id'))
          .map((d) => jsonDecode(d['data'] as String))
          .toList();
      expect(
          crud,
          equals([
            {
              "op": "PUT",
              "type": "customers",
              "id": customerId,
              "data": {"email": "test@example.org", "name": "test customer"}
            },
            {
              "op": "PUT",
              "type": "assets",
              "id": assetId,
              "data": {
                "user_id": userId,
                "customer_id": customerId,
                "description": "test."
              }
            }
          ]));
    });

    test('Watch correct table after switching schema', () async {
      // Start with "offline-only" schema.
      // This does not record any operations to the crud queue.
      var db =
          await testUtils.setupPowerSync(path: path, schema: makeSchema(false));

      final customerWatchTables =
          await getSourceTables(db, 'SELECT * FROM customers');

      expect(
          customerWatchTables.contains('ps_data_local__local_customers'), true);
      await db.updateSchema(makeSchema(true));
      await db.refreshSchema();

      final onlineCustomerWatchTables =
          await getSourceTables(db, 'SELECT * FROM customers');

      expect(onlineCustomerWatchTables.contains('ps_data__customers'), true);
    });
  });
}
