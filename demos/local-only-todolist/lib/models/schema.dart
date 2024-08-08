import 'package:powersync/powersync.dart';
import 'package:powersync_flutter_local_only_demo/models/sync_mode.dart';

/// This schema design supports a local-only to online workflow by managing data
/// across two versions of each table: one for local/offline use and one for
/// online/synced use. This approach simplifies the handling of data in different
/// connectivity states.
///
/// For local-only, the views become:
///   inactive_synced_todos
///   todos
///   inactive_synced_lists
///   lists
///
/// - 'todos' and 'lists' refer to the local-only data.
/// - 'inactive_synced_todos' and 'inactive_synced_lists' refer to the data that will be synced
///    once online.
///
/// For online, we have these views:
///   todos
///   inactive_local_todos
///   lists
///   inactive_local_lists
///
/// - 'todos' and 'lists' refer to the synced/online data.
/// - `inactive_local_todos' and 'inactive_local_lists' refer to the local-only data, allowing
///   for temporary storage or operations before syncing.
///
///  For an offline-to-online transition [switchToOnlineSchema] copies data so that it ends up in the upload queue.

const todosTable = 'todos';
const listsTable = 'lists';

Schema makeSchema({synced = bool}) {
  String onlineName(String table) {
    if (synced) {
      return table;
    } else {
      return "inactive_synced_$table";
    }
  }

  String localName(String table) {
    if (synced) {
      return "inactive_local_$table";
    } else {
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
          indexes: table.indexes, viewName: onlineName(table.name)),
    for (var table in tables)
      Table.localOnly('local_${table.name}', table.columns,
          indexes: table.indexes, viewName: localName(table.name))
  ]);
}

switchToOnlineSchema(PowerSyncDatabase db, String userId) async {
  await db.updateSchema(makeSchema(synced: true));
  await setSyncEnabled(true);

  await db.writeTransaction((tx) async {
    // Copy local-only data to the "online" views.
    // This records each operation to the crud queue.
    await tx.execute(
        'INSERT INTO lists(id, name, created_at, owner_id) SELECT id, name, created_at, ? FROM inactive_local_lists',
        [userId]);

    await tx.execute(
        'INSERT INTO $todosTable SELECT * FROM inactive_local_$todosTable');

    // Delete the "local-only" data.
    await tx.execute('DELETE FROM inactive_local_$todosTable');
    await tx.execute('DELETE FROM inactive_local_$listsTable');
  });
}
