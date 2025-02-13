// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'todo_list_page.dart';

// **************************************************************************
// DriftRiverpodGenerator
// **************************************************************************

extension on AppDatabase {
  Selectable<TodoItem> _todosIn(String var1) {
    return customSelect('SELECT * FROM todos WHERE list_id = ?1', variables: [
      Variable<String>(var1)
    ], readsFrom: {
      todoItems,
    }).asyncMap(todoItems.mapFromRow);
  }
}

extension on DatabaseProvider<AppDatabase> {
  SelectableProviderFamily<List<TodoItem>, (String list,)> watchTodos(
      Object _) {
    return queryProviderFamilyImpl(
        (ref, args) => ref.watch(driftDatabase)._todosIn(
              args.$1,
            ));
  }
}
