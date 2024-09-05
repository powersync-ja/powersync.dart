import 'package:powersync/powersync.dart';
import 'package:powersync_flutter_local_only_demo/models/sync_mode.dart';

/// This schema design supports a local-only to sync-enabled workflow by managing data
/// across two versions of each table: one for local-only use without syncing before a user registers, 
/// the other for sync-enabled use after the user registers/signs in.
/// 
/// This is done by utilizing the viewName property to override the default view name
/// of a table.
///
/// See the README for details.
///
/// [switchToSyncedSchema] copies data from the local-only tables to the sync-enabled tables
/// so that it ends up in the upload queue.

const todosTable = 'todos';
const listsTable = 'lists';

Schema makeSchema({synced = bool}) {
  String syncedName(String table) {
    if (synced) {
      // results in lists, todos
      return table;
    } else {
      // in the local-only mode of the demo
      // these tables are not used
      return "inactive_synced_$table";
    }
  }

  String localName(String table) {
    if (synced) {
      // in the sync-enabled mode of the demo
      // these tables are not used
      return "inactive_local_$table";
    } else {
      // results in lists, todos
      return table;
    }
  }

  final tables = [
    const Table(todosTable, [
      Column.text('list_id'),
      Column.text('created_at'),
      Column.text('completed_at'),
      Column.text('description'),
      Column.integer('completed'),
      Column.text('created_by'),
      Column.text('completed_by'),
    ], indexes: [
      // Index to allow efficient lookup within a list
      Index('list', [IndexedColumn('list_id')])
    ]),
    const Table(listsTable, [
      Column.text('created_at'),
      Column.text('name'),
      Column.text('owner_id')
    ])
  ];

  return Schema([
    for (var table in tables)
      Table(table.name, table.columns,
          indexes: table.indexes, viewName: syncedName(table.name)),
    for (var table in tables)
      Table.localOnly('local_${table.name}', table.columns,
          indexes: table.indexes, viewName: localName(table.name))
  ]);
}

switchToSyncedSchema(PowerSyncDatabase db, String userId) async {
  await db.updateSchema(makeSchema(synced: true));

  // needed to ensure that watches/queries are aware of the updated schema
  await db.refreshSchema();
  await setSyncEnabled(true);

  await db.writeTransaction((tx) async {
    // Copy local-only data to the sync-enabled views.
    // This records each operation in the upload queue.
    await tx.execute(
        'INSERT INTO $listsTable(id, name, created_at, owner_id) SELECT id, name, created_at, ? FROM inactive_local_$listsTable',
        [userId]);

    await tx.execute(
        'INSERT INTO $todosTable SELECT * FROM inactive_local_$todosTable');

    // Delete the local-only data.
    await tx.execute('DELETE FROM inactive_local_$todosTable');
    await tx.execute('DELETE FROM inactive_local_$listsTable');
  });
}
