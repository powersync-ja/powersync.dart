// dart format width=80
// ignore_for_file: type=lint
import 'package:drift/drift.dart' as i0;
import 'package:drift/internal/modular.dart' as i1;
import 'package:supabase_todolist_drift/powersync/database.dart' as i2;
import 'package:supabase_todolist_drift/powersync/database.drift.dart' as i3;

class QueriesDrift extends i1.ModularAccessor {
  QueriesDrift(i0.GeneratedDatabase db) : super(db);
  i0.Selectable<i2.ListItemWithStats> listsWithStats() {
    return customSelect(
        'SELECT"self"."id" AS "nested_0.id", "self"."created_at" AS "nested_0.created_at", "self"."name" AS "nested_0.name", "self"."owner_id" AS "nested_0.owner_id", (SELECT count() FROM todos WHERE list_id = self.id AND completed = TRUE) AS completed_count, (SELECT count() FROM todos WHERE list_id = self.id AND completed = FALSE) AS pending_count FROM lists AS self ORDER BY created_at',
        variables: [],
        readsFrom: {
          todoItems,
          listItems,
        }).asyncMap((i0.QueryRow row) async => i2.ListItemWithStats(
          await listItems.mapFromRow(row, tablePrefix: 'nested_0'),
          row.read<int>('completed_count'),
          row.read<int>('pending_count'),
        ));
  }

  i3.$ListItemsTable get listItems => i1.ReadDatabaseContainer(attachedDatabase)
      .resultSet<i3.$ListItemsTable>('lists');
  i3.$TodoItemsTable get todoItems => i1.ReadDatabaseContainer(attachedDatabase)
      .resultSet<i3.$TodoItemsTable>('todos');
}
