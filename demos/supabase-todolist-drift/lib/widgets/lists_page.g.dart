// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'lists_page.dart';

// **************************************************************************
// DriftRiverpodGenerator
// **************************************************************************

extension on AppDatabase {
  Selectable<ListItemWithStats> listsWithStats() {
    return customSelect(
        'SELECT"self"."id" AS "nested_0.id", "self"."created_at" AS "nested_0.created_at", "self"."name" AS "nested_0.name", "self"."owner_id" AS "nested_0.owner_id", (SELECT count() FROM todos WHERE list_id = self.id AND completed = TRUE) AS completed_count, (SELECT count() FROM todos WHERE list_id = self.id AND completed = FALSE) AS pending_count FROM lists AS self ORDER BY created_at',
        variables: [],
        readsFrom: {
          todoItems,
          listItems,
        }).asyncMap((QueryRow row) async => ListItemWithStats(
          await listItems.mapFromRow(row, tablePrefix: 'nested_0'),
          row.read<int>('completed_count'),
          row.read<int>('pending_count'),
        ));
  }
}

extension on DatabaseProvider<AppDatabase> {
  SelectableProvider<List<ListItemWithStats>> stats(String _) {
    return queryProviderImpl(
        (ref) => ref.watch(driftDatabase).listsWithStats());
  }
}
