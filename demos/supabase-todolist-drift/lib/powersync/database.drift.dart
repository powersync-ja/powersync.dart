// dart format width=80
// ignore_for_file: type=lint
import 'package:drift/drift.dart' as i0;
import 'package:supabase_todolist_drift/powersync/database.drift.dart' as i1;
import 'package:supabase_todolist_drift/powersync/queries.drift.dart' as i2;
import 'package:drift/internal/modular.dart' as i3;
import 'package:supabase_todolist_drift/powersync/database.dart' as i4;
import 'package:powersync_core/src/uuid.dart' as i5;

typedef $$TodoItemsTableCreateCompanionBuilder = i1.TodoItemsCompanion
    Function({
  i0.Value<String> id,
  required String listId,
  i0.Value<String?> photoId,
  i0.Value<DateTime?> createdAt,
  i0.Value<DateTime?> completedAt,
  i0.Value<bool?> completed,
  required String description,
  i0.Value<String?> createdBy,
  i0.Value<String?> completedBy,
  i0.Value<int> rowid,
});
typedef $$TodoItemsTableUpdateCompanionBuilder = i1.TodoItemsCompanion
    Function({
  i0.Value<String> id,
  i0.Value<String> listId,
  i0.Value<String?> photoId,
  i0.Value<DateTime?> createdAt,
  i0.Value<DateTime?> completedAt,
  i0.Value<bool?> completed,
  i0.Value<String> description,
  i0.Value<String?> createdBy,
  i0.Value<String?> completedBy,
  i0.Value<int> rowid,
});

final class $$TodoItemsTableReferences extends i0
    .BaseReferences<i0.GeneratedDatabase, i1.$TodoItemsTable, i1.TodoItem> {
  $$TodoItemsTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static i1.$ListItemsTable _listIdTable(i0.GeneratedDatabase db) =>
      i3.ReadDatabaseContainer(db)
          .resultSet<i1.$ListItemsTable>('lists')
          .createAlias(i0.$_aliasNameGenerator(
              i3.ReadDatabaseContainer(db)
                  .resultSet<i1.$TodoItemsTable>('todos')
                  .listId,
              i3.ReadDatabaseContainer(db)
                  .resultSet<i1.$ListItemsTable>('lists')
                  .id));

  i1.$$ListItemsTableProcessedTableManager get listId {
    final $_column = $_itemColumn<String>('list_id')!;

    final manager = i1
        .$$ListItemsTableTableManager(
            $_db,
            i3.ReadDatabaseContainer($_db)
                .resultSet<i1.$ListItemsTable>('lists'))
        .filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_listIdTable($_db));
    if (item == null) return manager;
    return i0.ProcessedTableManager(
        manager.$state.copyWith(prefetchedData: [item]));
  }
}

class $$TodoItemsTableFilterComposer
    extends i0.Composer<i0.GeneratedDatabase, i1.$TodoItemsTable> {
  $$TodoItemsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  i0.ColumnFilters<String> get id => $composableBuilder(
      column: $table.id, builder: (column) => i0.ColumnFilters(column));

  i0.ColumnFilters<String> get photoId => $composableBuilder(
      column: $table.photoId, builder: (column) => i0.ColumnFilters(column));

  i0.ColumnFilters<DateTime> get createdAt => $composableBuilder(
      column: $table.createdAt, builder: (column) => i0.ColumnFilters(column));

  i0.ColumnFilters<DateTime> get completedAt => $composableBuilder(
      column: $table.completedAt,
      builder: (column) => i0.ColumnFilters(column));

  i0.ColumnFilters<bool> get completed => $composableBuilder(
      column: $table.completed, builder: (column) => i0.ColumnFilters(column));

  i0.ColumnFilters<String> get description => $composableBuilder(
      column: $table.description,
      builder: (column) => i0.ColumnFilters(column));

  i0.ColumnFilters<String> get createdBy => $composableBuilder(
      column: $table.createdBy, builder: (column) => i0.ColumnFilters(column));

  i0.ColumnFilters<String> get completedBy => $composableBuilder(
      column: $table.completedBy,
      builder: (column) => i0.ColumnFilters(column));

  i1.$$ListItemsTableFilterComposer get listId {
    final i1.$$ListItemsTableFilterComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.listId,
        referencedTable: i3.ReadDatabaseContainer($db)
            .resultSet<i1.$ListItemsTable>('lists'),
        getReferencedColumn: (t) => t.id,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            i1.$$ListItemsTableFilterComposer(
              $db: $db,
              $table: i3.ReadDatabaseContainer($db)
                  .resultSet<i1.$ListItemsTable>('lists'),
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return composer;
  }
}

class $$TodoItemsTableOrderingComposer
    extends i0.Composer<i0.GeneratedDatabase, i1.$TodoItemsTable> {
  $$TodoItemsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  i0.ColumnOrderings<String> get id => $composableBuilder(
      column: $table.id, builder: (column) => i0.ColumnOrderings(column));

  i0.ColumnOrderings<String> get photoId => $composableBuilder(
      column: $table.photoId, builder: (column) => i0.ColumnOrderings(column));

  i0.ColumnOrderings<DateTime> get createdAt => $composableBuilder(
      column: $table.createdAt,
      builder: (column) => i0.ColumnOrderings(column));

  i0.ColumnOrderings<DateTime> get completedAt => $composableBuilder(
      column: $table.completedAt,
      builder: (column) => i0.ColumnOrderings(column));

  i0.ColumnOrderings<bool> get completed => $composableBuilder(
      column: $table.completed,
      builder: (column) => i0.ColumnOrderings(column));

  i0.ColumnOrderings<String> get description => $composableBuilder(
      column: $table.description,
      builder: (column) => i0.ColumnOrderings(column));

  i0.ColumnOrderings<String> get createdBy => $composableBuilder(
      column: $table.createdBy,
      builder: (column) => i0.ColumnOrderings(column));

  i0.ColumnOrderings<String> get completedBy => $composableBuilder(
      column: $table.completedBy,
      builder: (column) => i0.ColumnOrderings(column));

  i1.$$ListItemsTableOrderingComposer get listId {
    final i1.$$ListItemsTableOrderingComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.listId,
        referencedTable: i3.ReadDatabaseContainer($db)
            .resultSet<i1.$ListItemsTable>('lists'),
        getReferencedColumn: (t) => t.id,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            i1.$$ListItemsTableOrderingComposer(
              $db: $db,
              $table: i3.ReadDatabaseContainer($db)
                  .resultSet<i1.$ListItemsTable>('lists'),
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return composer;
  }
}

class $$TodoItemsTableAnnotationComposer
    extends i0.Composer<i0.GeneratedDatabase, i1.$TodoItemsTable> {
  $$TodoItemsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  i0.GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  i0.GeneratedColumn<String> get photoId =>
      $composableBuilder(column: $table.photoId, builder: (column) => column);

  i0.GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  i0.GeneratedColumn<DateTime> get completedAt => $composableBuilder(
      column: $table.completedAt, builder: (column) => column);

  i0.GeneratedColumn<bool> get completed =>
      $composableBuilder(column: $table.completed, builder: (column) => column);

  i0.GeneratedColumn<String> get description => $composableBuilder(
      column: $table.description, builder: (column) => column);

  i0.GeneratedColumn<String> get createdBy =>
      $composableBuilder(column: $table.createdBy, builder: (column) => column);

  i0.GeneratedColumn<String> get completedBy => $composableBuilder(
      column: $table.completedBy, builder: (column) => column);

  i1.$$ListItemsTableAnnotationComposer get listId {
    final i1.$$ListItemsTableAnnotationComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.listId,
        referencedTable: i3.ReadDatabaseContainer($db)
            .resultSet<i1.$ListItemsTable>('lists'),
        getReferencedColumn: (t) => t.id,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            i1.$$ListItemsTableAnnotationComposer(
              $db: $db,
              $table: i3.ReadDatabaseContainer($db)
                  .resultSet<i1.$ListItemsTable>('lists'),
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return composer;
  }
}

class $$TodoItemsTableTableManager extends i0.RootTableManager<
    i0.GeneratedDatabase,
    i1.$TodoItemsTable,
    i1.TodoItem,
    i1.$$TodoItemsTableFilterComposer,
    i1.$$TodoItemsTableOrderingComposer,
    i1.$$TodoItemsTableAnnotationComposer,
    $$TodoItemsTableCreateCompanionBuilder,
    $$TodoItemsTableUpdateCompanionBuilder,
    (i1.TodoItem, i1.$$TodoItemsTableReferences),
    i1.TodoItem,
    i0.PrefetchHooks Function({bool listId})> {
  $$TodoItemsTableTableManager(
      i0.GeneratedDatabase db, i1.$TodoItemsTable table)
      : super(i0.TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              i1.$$TodoItemsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              i1.$$TodoItemsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              i1.$$TodoItemsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            i0.Value<String> id = const i0.Value.absent(),
            i0.Value<String> listId = const i0.Value.absent(),
            i0.Value<String?> photoId = const i0.Value.absent(),
            i0.Value<DateTime?> createdAt = const i0.Value.absent(),
            i0.Value<DateTime?> completedAt = const i0.Value.absent(),
            i0.Value<bool?> completed = const i0.Value.absent(),
            i0.Value<String> description = const i0.Value.absent(),
            i0.Value<String?> createdBy = const i0.Value.absent(),
            i0.Value<String?> completedBy = const i0.Value.absent(),
            i0.Value<int> rowid = const i0.Value.absent(),
          }) =>
              i1.TodoItemsCompanion(
            id: id,
            listId: listId,
            photoId: photoId,
            createdAt: createdAt,
            completedAt: completedAt,
            completed: completed,
            description: description,
            createdBy: createdBy,
            completedBy: completedBy,
            rowid: rowid,
          ),
          createCompanionCallback: ({
            i0.Value<String> id = const i0.Value.absent(),
            required String listId,
            i0.Value<String?> photoId = const i0.Value.absent(),
            i0.Value<DateTime?> createdAt = const i0.Value.absent(),
            i0.Value<DateTime?> completedAt = const i0.Value.absent(),
            i0.Value<bool?> completed = const i0.Value.absent(),
            required String description,
            i0.Value<String?> createdBy = const i0.Value.absent(),
            i0.Value<String?> completedBy = const i0.Value.absent(),
            i0.Value<int> rowid = const i0.Value.absent(),
          }) =>
              i1.TodoItemsCompanion.insert(
            id: id,
            listId: listId,
            photoId: photoId,
            createdAt: createdAt,
            completedAt: completedAt,
            completed: completed,
            description: description,
            createdBy: createdBy,
            completedBy: completedBy,
            rowid: rowid,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (
                    e.readTable(table),
                    i1.$$TodoItemsTableReferences(db, table, e)
                  ))
              .toList(),
          prefetchHooksCallback: ({listId = false}) {
            return i0.PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [],
              addJoins: <
                  T extends i0.TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic>>(state) {
                if (listId) {
                  state = state.withJoin(
                    currentTable: table,
                    currentColumn: table.listId,
                    referencedTable:
                        i1.$$TodoItemsTableReferences._listIdTable(db),
                    referencedColumn:
                        i1.$$TodoItemsTableReferences._listIdTable(db).id,
                  ) as T;
                }

                return state;
              },
              getPrefetchedDataCallback: (items) async {
                return [];
              },
            );
          },
        ));
}

typedef $$TodoItemsTableProcessedTableManager = i0.ProcessedTableManager<
    i0.GeneratedDatabase,
    i1.$TodoItemsTable,
    i1.TodoItem,
    i1.$$TodoItemsTableFilterComposer,
    i1.$$TodoItemsTableOrderingComposer,
    i1.$$TodoItemsTableAnnotationComposer,
    $$TodoItemsTableCreateCompanionBuilder,
    $$TodoItemsTableUpdateCompanionBuilder,
    (i1.TodoItem, i1.$$TodoItemsTableReferences),
    i1.TodoItem,
    i0.PrefetchHooks Function({bool listId})>;
typedef $$ListItemsTableCreateCompanionBuilder = i1.ListItemsCompanion
    Function({
  i0.Value<String> id,
  i0.Value<DateTime> createdAt,
  required String name,
  i0.Value<String?> ownerId,
  i0.Value<int> rowid,
});
typedef $$ListItemsTableUpdateCompanionBuilder = i1.ListItemsCompanion
    Function({
  i0.Value<String> id,
  i0.Value<DateTime> createdAt,
  i0.Value<String> name,
  i0.Value<String?> ownerId,
  i0.Value<int> rowid,
});

final class $$ListItemsTableReferences extends i0
    .BaseReferences<i0.GeneratedDatabase, i1.$ListItemsTable, i1.ListItem> {
  $$ListItemsTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static i0.MultiTypedResultKey<i1.$TodoItemsTable, List<i1.TodoItem>>
      _todoItemsRefsTable(i0.GeneratedDatabase db) =>
          i0.MultiTypedResultKey.fromTable(
              i3.ReadDatabaseContainer(db)
                  .resultSet<i1.$TodoItemsTable>('todos'),
              aliasName: i0.$_aliasNameGenerator(
                  i3.ReadDatabaseContainer(db)
                      .resultSet<i1.$ListItemsTable>('lists')
                      .id,
                  i3.ReadDatabaseContainer(db)
                      .resultSet<i1.$TodoItemsTable>('todos')
                      .listId));

  i1.$$TodoItemsTableProcessedTableManager get todoItemsRefs {
    final manager = i1
        .$$TodoItemsTableTableManager(
            $_db,
            i3.ReadDatabaseContainer($_db)
                .resultSet<i1.$TodoItemsTable>('todos'))
        .filter((f) => f.listId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(_todoItemsRefsTable($_db));
    return i0.ProcessedTableManager(
        manager.$state.copyWith(prefetchedData: cache));
  }
}

class $$ListItemsTableFilterComposer
    extends i0.Composer<i0.GeneratedDatabase, i1.$ListItemsTable> {
  $$ListItemsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  i0.ColumnFilters<String> get id => $composableBuilder(
      column: $table.id, builder: (column) => i0.ColumnFilters(column));

  i0.ColumnFilters<DateTime> get createdAt => $composableBuilder(
      column: $table.createdAt, builder: (column) => i0.ColumnFilters(column));

  i0.ColumnFilters<String> get name => $composableBuilder(
      column: $table.name, builder: (column) => i0.ColumnFilters(column));

  i0.ColumnFilters<String> get ownerId => $composableBuilder(
      column: $table.ownerId, builder: (column) => i0.ColumnFilters(column));

  i0.Expression<bool> todoItemsRefs(
      i0.Expression<bool> Function(i1.$$TodoItemsTableFilterComposer f) f) {
    final i1.$$TodoItemsTableFilterComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.id,
        referencedTable: i3.ReadDatabaseContainer($db)
            .resultSet<i1.$TodoItemsTable>('todos'),
        getReferencedColumn: (t) => t.listId,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            i1.$$TodoItemsTableFilterComposer(
              $db: $db,
              $table: i3.ReadDatabaseContainer($db)
                  .resultSet<i1.$TodoItemsTable>('todos'),
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return f(composer);
  }
}

class $$ListItemsTableOrderingComposer
    extends i0.Composer<i0.GeneratedDatabase, i1.$ListItemsTable> {
  $$ListItemsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  i0.ColumnOrderings<String> get id => $composableBuilder(
      column: $table.id, builder: (column) => i0.ColumnOrderings(column));

  i0.ColumnOrderings<DateTime> get createdAt => $composableBuilder(
      column: $table.createdAt,
      builder: (column) => i0.ColumnOrderings(column));

  i0.ColumnOrderings<String> get name => $composableBuilder(
      column: $table.name, builder: (column) => i0.ColumnOrderings(column));

  i0.ColumnOrderings<String> get ownerId => $composableBuilder(
      column: $table.ownerId, builder: (column) => i0.ColumnOrderings(column));
}

class $$ListItemsTableAnnotationComposer
    extends i0.Composer<i0.GeneratedDatabase, i1.$ListItemsTable> {
  $$ListItemsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  i0.GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  i0.GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  i0.GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  i0.GeneratedColumn<String> get ownerId =>
      $composableBuilder(column: $table.ownerId, builder: (column) => column);

  i0.Expression<T> todoItemsRefs<T extends Object>(
      i0.Expression<T> Function(i1.$$TodoItemsTableAnnotationComposer a) f) {
    final i1.$$TodoItemsTableAnnotationComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.id,
        referencedTable: i3.ReadDatabaseContainer($db)
            .resultSet<i1.$TodoItemsTable>('todos'),
        getReferencedColumn: (t) => t.listId,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            i1.$$TodoItemsTableAnnotationComposer(
              $db: $db,
              $table: i3.ReadDatabaseContainer($db)
                  .resultSet<i1.$TodoItemsTable>('todos'),
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return f(composer);
  }
}

class $$ListItemsTableTableManager extends i0.RootTableManager<
    i0.GeneratedDatabase,
    i1.$ListItemsTable,
    i1.ListItem,
    i1.$$ListItemsTableFilterComposer,
    i1.$$ListItemsTableOrderingComposer,
    i1.$$ListItemsTableAnnotationComposer,
    $$ListItemsTableCreateCompanionBuilder,
    $$ListItemsTableUpdateCompanionBuilder,
    (i1.ListItem, i1.$$ListItemsTableReferences),
    i1.ListItem,
    i0.PrefetchHooks Function({bool todoItemsRefs})> {
  $$ListItemsTableTableManager(
      i0.GeneratedDatabase db, i1.$ListItemsTable table)
      : super(i0.TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              i1.$$ListItemsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              i1.$$ListItemsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              i1.$$ListItemsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            i0.Value<String> id = const i0.Value.absent(),
            i0.Value<DateTime> createdAt = const i0.Value.absent(),
            i0.Value<String> name = const i0.Value.absent(),
            i0.Value<String?> ownerId = const i0.Value.absent(),
            i0.Value<int> rowid = const i0.Value.absent(),
          }) =>
              i1.ListItemsCompanion(
            id: id,
            createdAt: createdAt,
            name: name,
            ownerId: ownerId,
            rowid: rowid,
          ),
          createCompanionCallback: ({
            i0.Value<String> id = const i0.Value.absent(),
            i0.Value<DateTime> createdAt = const i0.Value.absent(),
            required String name,
            i0.Value<String?> ownerId = const i0.Value.absent(),
            i0.Value<int> rowid = const i0.Value.absent(),
          }) =>
              i1.ListItemsCompanion.insert(
            id: id,
            createdAt: createdAt,
            name: name,
            ownerId: ownerId,
            rowid: rowid,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (
                    e.readTable(table),
                    i1.$$ListItemsTableReferences(db, table, e)
                  ))
              .toList(),
          prefetchHooksCallback: ({todoItemsRefs = false}) {
            return i0.PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [
                if (todoItemsRefs)
                  i3.ReadDatabaseContainer(db)
                      .resultSet<i1.$TodoItemsTable>('todos')
              ],
              addJoins: null,
              getPrefetchedDataCallback: (items) async {
                return [
                  if (todoItemsRefs)
                    await i0.$_getPrefetchedData<i1.ListItem,
                            i1.$ListItemsTable, i1.TodoItem>(
                        currentTable: table,
                        referencedTable: i1.$$ListItemsTableReferences
                            ._todoItemsRefsTable(db),
                        managerFromTypedResult: (p0) => i1
                            .$$ListItemsTableReferences(db, table, p0)
                            .todoItemsRefs,
                        referencedItemsForCurrentItem: (item,
                                referencedItems) =>
                            referencedItems.where((e) => e.listId == item.id),
                        typedResults: items)
                ];
              },
            );
          },
        ));
}

typedef $$ListItemsTableProcessedTableManager = i0.ProcessedTableManager<
    i0.GeneratedDatabase,
    i1.$ListItemsTable,
    i1.ListItem,
    i1.$$ListItemsTableFilterComposer,
    i1.$$ListItemsTableOrderingComposer,
    i1.$$ListItemsTableAnnotationComposer,
    $$ListItemsTableCreateCompanionBuilder,
    $$ListItemsTableUpdateCompanionBuilder,
    (i1.ListItem, i1.$$ListItemsTableReferences),
    i1.ListItem,
    i0.PrefetchHooks Function({bool todoItemsRefs})>;

abstract class $AppDatabase extends i0.GeneratedDatabase {
  $AppDatabase(i0.QueryExecutor e) : super(e);
  $AppDatabaseManager get managers => $AppDatabaseManager(this);
  late final i1.$ListItemsTable listItems = i1.$ListItemsTable(this);
  late final i1.$TodoItemsTable todoItems = i1.$TodoItemsTable(this);
  i2.QueriesDrift get queriesDrift => i3.ReadDatabaseContainer(this)
      .accessor<i2.QueriesDrift>(i2.QueriesDrift.new);
  @override
  Iterable<i0.TableInfo<i0.Table, Object?>> get allTables =>
      allSchemaEntities.whereType<i0.TableInfo<i0.Table, Object?>>();
  @override
  List<i0.DatabaseSchemaEntity> get allSchemaEntities => [listItems, todoItems];
  @override
  i0.DriftDatabaseOptions get options =>
      const i0.DriftDatabaseOptions(storeDateTimeAsText: true);
}

class $AppDatabaseManager {
  final $AppDatabase _db;
  $AppDatabaseManager(this._db);
  i1.$$ListItemsTableTableManager get listItems =>
      i1.$$ListItemsTableTableManager(_db, _db.listItems);
  i1.$$TodoItemsTableTableManager get todoItems =>
      i1.$$TodoItemsTableTableManager(_db, _db.todoItems);
}

class $TodoItemsTable extends i4.TodoItems
    with i0.TableInfo<$TodoItemsTable, i1.TodoItem> {
  @override
  final i0.GeneratedDatabase attachedDatabase;
  final String? _alias;
  $TodoItemsTable(this.attachedDatabase, [this._alias]);
  static const i0.VerificationMeta _idMeta = const i0.VerificationMeta('id');
  @override
  late final i0.GeneratedColumn<String> id = i0.GeneratedColumn<String>(
      'id', aliasedName, false,
      type: i0.DriftSqlType.string,
      requiredDuringInsert: false,
      clientDefault: () => i5.uuid.v4());
  static const i0.VerificationMeta _listIdMeta =
      const i0.VerificationMeta('listId');
  @override
  late final i0.GeneratedColumn<String> listId = i0.GeneratedColumn<String>(
      'list_id', aliasedName, false,
      type: i0.DriftSqlType.string,
      requiredDuringInsert: true,
      defaultConstraints:
          i0.GeneratedColumn.constraintIsAlways('REFERENCES lists (id)'));
  static const i0.VerificationMeta _photoIdMeta =
      const i0.VerificationMeta('photoId');
  @override
  late final i0.GeneratedColumn<String> photoId = i0.GeneratedColumn<String>(
      'photo_id', aliasedName, true,
      type: i0.DriftSqlType.string, requiredDuringInsert: false);
  static const i0.VerificationMeta _createdAtMeta =
      const i0.VerificationMeta('createdAt');
  @override
  late final i0.GeneratedColumn<DateTime> createdAt =
      i0.GeneratedColumn<DateTime>('created_at', aliasedName, true,
          type: i0.DriftSqlType.dateTime, requiredDuringInsert: false);
  static const i0.VerificationMeta _completedAtMeta =
      const i0.VerificationMeta('completedAt');
  @override
  late final i0.GeneratedColumn<DateTime> completedAt =
      i0.GeneratedColumn<DateTime>('completed_at', aliasedName, true,
          type: i0.DriftSqlType.dateTime, requiredDuringInsert: false);
  static const i0.VerificationMeta _completedMeta =
      const i0.VerificationMeta('completed');
  @override
  late final i0.GeneratedColumn<bool> completed = i0.GeneratedColumn<bool>(
      'completed', aliasedName, true,
      type: i0.DriftSqlType.bool,
      requiredDuringInsert: false,
      defaultConstraints: i0.GeneratedColumn.constraintIsAlways(
          'CHECK ("completed" IN (0, 1))'));
  static const i0.VerificationMeta _descriptionMeta =
      const i0.VerificationMeta('description');
  @override
  late final i0.GeneratedColumn<String> description =
      i0.GeneratedColumn<String>('description', aliasedName, false,
          type: i0.DriftSqlType.string, requiredDuringInsert: true);
  static const i0.VerificationMeta _createdByMeta =
      const i0.VerificationMeta('createdBy');
  @override
  late final i0.GeneratedColumn<String> createdBy = i0.GeneratedColumn<String>(
      'created_by', aliasedName, true,
      type: i0.DriftSqlType.string, requiredDuringInsert: false);
  static const i0.VerificationMeta _completedByMeta =
      const i0.VerificationMeta('completedBy');
  @override
  late final i0.GeneratedColumn<String> completedBy =
      i0.GeneratedColumn<String>('completed_by', aliasedName, true,
          type: i0.DriftSqlType.string, requiredDuringInsert: false);
  @override
  List<i0.GeneratedColumn> get $columns => [
        id,
        listId,
        photoId,
        createdAt,
        completedAt,
        completed,
        description,
        createdBy,
        completedBy
      ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'todos';
  @override
  i0.VerificationContext validateIntegrity(i0.Insertable<i1.TodoItem> instance,
      {bool isInserting = false}) {
    final context = i0.VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('list_id')) {
      context.handle(_listIdMeta,
          listId.isAcceptableOrUnknown(data['list_id']!, _listIdMeta));
    } else if (isInserting) {
      context.missing(_listIdMeta);
    }
    if (data.containsKey('photo_id')) {
      context.handle(_photoIdMeta,
          photoId.isAcceptableOrUnknown(data['photo_id']!, _photoIdMeta));
    }
    if (data.containsKey('created_at')) {
      context.handle(_createdAtMeta,
          createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta));
    }
    if (data.containsKey('completed_at')) {
      context.handle(
          _completedAtMeta,
          completedAt.isAcceptableOrUnknown(
              data['completed_at']!, _completedAtMeta));
    }
    if (data.containsKey('completed')) {
      context.handle(_completedMeta,
          completed.isAcceptableOrUnknown(data['completed']!, _completedMeta));
    }
    if (data.containsKey('description')) {
      context.handle(
          _descriptionMeta,
          description.isAcceptableOrUnknown(
              data['description']!, _descriptionMeta));
    } else if (isInserting) {
      context.missing(_descriptionMeta);
    }
    if (data.containsKey('created_by')) {
      context.handle(_createdByMeta,
          createdBy.isAcceptableOrUnknown(data['created_by']!, _createdByMeta));
    }
    if (data.containsKey('completed_by')) {
      context.handle(
          _completedByMeta,
          completedBy.isAcceptableOrUnknown(
              data['completed_by']!, _completedByMeta));
    }
    return context;
  }

  @override
  Set<i0.GeneratedColumn> get $primaryKey => const {};
  @override
  i1.TodoItem map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return i1.TodoItem(
      id: attachedDatabase.typeMapping
          .read(i0.DriftSqlType.string, data['${effectivePrefix}id'])!,
      listId: attachedDatabase.typeMapping
          .read(i0.DriftSqlType.string, data['${effectivePrefix}list_id'])!,
      photoId: attachedDatabase.typeMapping
          .read(i0.DriftSqlType.string, data['${effectivePrefix}photo_id']),
      createdAt: attachedDatabase.typeMapping
          .read(i0.DriftSqlType.dateTime, data['${effectivePrefix}created_at']),
      completedAt: attachedDatabase.typeMapping.read(
          i0.DriftSqlType.dateTime, data['${effectivePrefix}completed_at']),
      completed: attachedDatabase.typeMapping
          .read(i0.DriftSqlType.bool, data['${effectivePrefix}completed']),
      description: attachedDatabase.typeMapping
          .read(i0.DriftSqlType.string, data['${effectivePrefix}description'])!,
      createdBy: attachedDatabase.typeMapping
          .read(i0.DriftSqlType.string, data['${effectivePrefix}created_by']),
      completedBy: attachedDatabase.typeMapping
          .read(i0.DriftSqlType.string, data['${effectivePrefix}completed_by']),
    );
  }

  @override
  $TodoItemsTable createAlias(String alias) {
    return $TodoItemsTable(attachedDatabase, alias);
  }
}

class TodoItem extends i0.DataClass implements i0.Insertable<i1.TodoItem> {
  final String id;
  final String listId;
  final String? photoId;
  final DateTime? createdAt;
  final DateTime? completedAt;
  final bool? completed;
  final String description;
  final String? createdBy;
  final String? completedBy;
  const TodoItem(
      {required this.id,
      required this.listId,
      this.photoId,
      this.createdAt,
      this.completedAt,
      this.completed,
      required this.description,
      this.createdBy,
      this.completedBy});
  @override
  Map<String, i0.Expression> toColumns(bool nullToAbsent) {
    final map = <String, i0.Expression>{};
    map['id'] = i0.Variable<String>(id);
    map['list_id'] = i0.Variable<String>(listId);
    if (!nullToAbsent || photoId != null) {
      map['photo_id'] = i0.Variable<String>(photoId);
    }
    if (!nullToAbsent || createdAt != null) {
      map['created_at'] = i0.Variable<DateTime>(createdAt);
    }
    if (!nullToAbsent || completedAt != null) {
      map['completed_at'] = i0.Variable<DateTime>(completedAt);
    }
    if (!nullToAbsent || completed != null) {
      map['completed'] = i0.Variable<bool>(completed);
    }
    map['description'] = i0.Variable<String>(description);
    if (!nullToAbsent || createdBy != null) {
      map['created_by'] = i0.Variable<String>(createdBy);
    }
    if (!nullToAbsent || completedBy != null) {
      map['completed_by'] = i0.Variable<String>(completedBy);
    }
    return map;
  }

  i1.TodoItemsCompanion toCompanion(bool nullToAbsent) {
    return i1.TodoItemsCompanion(
      id: i0.Value(id),
      listId: i0.Value(listId),
      photoId: photoId == null && nullToAbsent
          ? const i0.Value.absent()
          : i0.Value(photoId),
      createdAt: createdAt == null && nullToAbsent
          ? const i0.Value.absent()
          : i0.Value(createdAt),
      completedAt: completedAt == null && nullToAbsent
          ? const i0.Value.absent()
          : i0.Value(completedAt),
      completed: completed == null && nullToAbsent
          ? const i0.Value.absent()
          : i0.Value(completed),
      description: i0.Value(description),
      createdBy: createdBy == null && nullToAbsent
          ? const i0.Value.absent()
          : i0.Value(createdBy),
      completedBy: completedBy == null && nullToAbsent
          ? const i0.Value.absent()
          : i0.Value(completedBy),
    );
  }

  factory TodoItem.fromJson(Map<String, dynamic> json,
      {i0.ValueSerializer? serializer}) {
    serializer ??= i0.driftRuntimeOptions.defaultSerializer;
    return TodoItem(
      id: serializer.fromJson<String>(json['id']),
      listId: serializer.fromJson<String>(json['listId']),
      photoId: serializer.fromJson<String?>(json['photoId']),
      createdAt: serializer.fromJson<DateTime?>(json['createdAt']),
      completedAt: serializer.fromJson<DateTime?>(json['completedAt']),
      completed: serializer.fromJson<bool?>(json['completed']),
      description: serializer.fromJson<String>(json['description']),
      createdBy: serializer.fromJson<String?>(json['createdBy']),
      completedBy: serializer.fromJson<String?>(json['completedBy']),
    );
  }
  @override
  Map<String, dynamic> toJson({i0.ValueSerializer? serializer}) {
    serializer ??= i0.driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'listId': serializer.toJson<String>(listId),
      'photoId': serializer.toJson<String?>(photoId),
      'createdAt': serializer.toJson<DateTime?>(createdAt),
      'completedAt': serializer.toJson<DateTime?>(completedAt),
      'completed': serializer.toJson<bool?>(completed),
      'description': serializer.toJson<String>(description),
      'createdBy': serializer.toJson<String?>(createdBy),
      'completedBy': serializer.toJson<String?>(completedBy),
    };
  }

  i1.TodoItem copyWith(
          {String? id,
          String? listId,
          i0.Value<String?> photoId = const i0.Value.absent(),
          i0.Value<DateTime?> createdAt = const i0.Value.absent(),
          i0.Value<DateTime?> completedAt = const i0.Value.absent(),
          i0.Value<bool?> completed = const i0.Value.absent(),
          String? description,
          i0.Value<String?> createdBy = const i0.Value.absent(),
          i0.Value<String?> completedBy = const i0.Value.absent()}) =>
      i1.TodoItem(
        id: id ?? this.id,
        listId: listId ?? this.listId,
        photoId: photoId.present ? photoId.value : this.photoId,
        createdAt: createdAt.present ? createdAt.value : this.createdAt,
        completedAt: completedAt.present ? completedAt.value : this.completedAt,
        completed: completed.present ? completed.value : this.completed,
        description: description ?? this.description,
        createdBy: createdBy.present ? createdBy.value : this.createdBy,
        completedBy: completedBy.present ? completedBy.value : this.completedBy,
      );
  TodoItem copyWithCompanion(i1.TodoItemsCompanion data) {
    return TodoItem(
      id: data.id.present ? data.id.value : this.id,
      listId: data.listId.present ? data.listId.value : this.listId,
      photoId: data.photoId.present ? data.photoId.value : this.photoId,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      completedAt:
          data.completedAt.present ? data.completedAt.value : this.completedAt,
      completed: data.completed.present ? data.completed.value : this.completed,
      description:
          data.description.present ? data.description.value : this.description,
      createdBy: data.createdBy.present ? data.createdBy.value : this.createdBy,
      completedBy:
          data.completedBy.present ? data.completedBy.value : this.completedBy,
    );
  }

  @override
  String toString() {
    return (StringBuffer('TodoItem(')
          ..write('id: $id, ')
          ..write('listId: $listId, ')
          ..write('photoId: $photoId, ')
          ..write('createdAt: $createdAt, ')
          ..write('completedAt: $completedAt, ')
          ..write('completed: $completed, ')
          ..write('description: $description, ')
          ..write('createdBy: $createdBy, ')
          ..write('completedBy: $completedBy')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, listId, photoId, createdAt, completedAt,
      completed, description, createdBy, completedBy);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is i1.TodoItem &&
          other.id == this.id &&
          other.listId == this.listId &&
          other.photoId == this.photoId &&
          other.createdAt == this.createdAt &&
          other.completedAt == this.completedAt &&
          other.completed == this.completed &&
          other.description == this.description &&
          other.createdBy == this.createdBy &&
          other.completedBy == this.completedBy);
}

class TodoItemsCompanion extends i0.UpdateCompanion<i1.TodoItem> {
  final i0.Value<String> id;
  final i0.Value<String> listId;
  final i0.Value<String?> photoId;
  final i0.Value<DateTime?> createdAt;
  final i0.Value<DateTime?> completedAt;
  final i0.Value<bool?> completed;
  final i0.Value<String> description;
  final i0.Value<String?> createdBy;
  final i0.Value<String?> completedBy;
  final i0.Value<int> rowid;
  const TodoItemsCompanion({
    this.id = const i0.Value.absent(),
    this.listId = const i0.Value.absent(),
    this.photoId = const i0.Value.absent(),
    this.createdAt = const i0.Value.absent(),
    this.completedAt = const i0.Value.absent(),
    this.completed = const i0.Value.absent(),
    this.description = const i0.Value.absent(),
    this.createdBy = const i0.Value.absent(),
    this.completedBy = const i0.Value.absent(),
    this.rowid = const i0.Value.absent(),
  });
  TodoItemsCompanion.insert({
    this.id = const i0.Value.absent(),
    required String listId,
    this.photoId = const i0.Value.absent(),
    this.createdAt = const i0.Value.absent(),
    this.completedAt = const i0.Value.absent(),
    this.completed = const i0.Value.absent(),
    required String description,
    this.createdBy = const i0.Value.absent(),
    this.completedBy = const i0.Value.absent(),
    this.rowid = const i0.Value.absent(),
  })  : listId = i0.Value(listId),
        description = i0.Value(description);
  static i0.Insertable<i1.TodoItem> custom({
    i0.Expression<String>? id,
    i0.Expression<String>? listId,
    i0.Expression<String>? photoId,
    i0.Expression<DateTime>? createdAt,
    i0.Expression<DateTime>? completedAt,
    i0.Expression<bool>? completed,
    i0.Expression<String>? description,
    i0.Expression<String>? createdBy,
    i0.Expression<String>? completedBy,
    i0.Expression<int>? rowid,
  }) {
    return i0.RawValuesInsertable({
      if (id != null) 'id': id,
      if (listId != null) 'list_id': listId,
      if (photoId != null) 'photo_id': photoId,
      if (createdAt != null) 'created_at': createdAt,
      if (completedAt != null) 'completed_at': completedAt,
      if (completed != null) 'completed': completed,
      if (description != null) 'description': description,
      if (createdBy != null) 'created_by': createdBy,
      if (completedBy != null) 'completed_by': completedBy,
      if (rowid != null) 'rowid': rowid,
    });
  }

  i1.TodoItemsCompanion copyWith(
      {i0.Value<String>? id,
      i0.Value<String>? listId,
      i0.Value<String?>? photoId,
      i0.Value<DateTime?>? createdAt,
      i0.Value<DateTime?>? completedAt,
      i0.Value<bool?>? completed,
      i0.Value<String>? description,
      i0.Value<String?>? createdBy,
      i0.Value<String?>? completedBy,
      i0.Value<int>? rowid}) {
    return i1.TodoItemsCompanion(
      id: id ?? this.id,
      listId: listId ?? this.listId,
      photoId: photoId ?? this.photoId,
      createdAt: createdAt ?? this.createdAt,
      completedAt: completedAt ?? this.completedAt,
      completed: completed ?? this.completed,
      description: description ?? this.description,
      createdBy: createdBy ?? this.createdBy,
      completedBy: completedBy ?? this.completedBy,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, i0.Expression> toColumns(bool nullToAbsent) {
    final map = <String, i0.Expression>{};
    if (id.present) {
      map['id'] = i0.Variable<String>(id.value);
    }
    if (listId.present) {
      map['list_id'] = i0.Variable<String>(listId.value);
    }
    if (photoId.present) {
      map['photo_id'] = i0.Variable<String>(photoId.value);
    }
    if (createdAt.present) {
      map['created_at'] = i0.Variable<DateTime>(createdAt.value);
    }
    if (completedAt.present) {
      map['completed_at'] = i0.Variable<DateTime>(completedAt.value);
    }
    if (completed.present) {
      map['completed'] = i0.Variable<bool>(completed.value);
    }
    if (description.present) {
      map['description'] = i0.Variable<String>(description.value);
    }
    if (createdBy.present) {
      map['created_by'] = i0.Variable<String>(createdBy.value);
    }
    if (completedBy.present) {
      map['completed_by'] = i0.Variable<String>(completedBy.value);
    }
    if (rowid.present) {
      map['rowid'] = i0.Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('TodoItemsCompanion(')
          ..write('id: $id, ')
          ..write('listId: $listId, ')
          ..write('photoId: $photoId, ')
          ..write('createdAt: $createdAt, ')
          ..write('completedAt: $completedAt, ')
          ..write('completed: $completed, ')
          ..write('description: $description, ')
          ..write('createdBy: $createdBy, ')
          ..write('completedBy: $completedBy, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $ListItemsTable extends i4.ListItems
    with i0.TableInfo<$ListItemsTable, i1.ListItem> {
  @override
  final i0.GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ListItemsTable(this.attachedDatabase, [this._alias]);
  static const i0.VerificationMeta _idMeta = const i0.VerificationMeta('id');
  @override
  late final i0.GeneratedColumn<String> id = i0.GeneratedColumn<String>(
      'id', aliasedName, false,
      type: i0.DriftSqlType.string,
      requiredDuringInsert: false,
      clientDefault: () => i5.uuid.v4());
  static const i0.VerificationMeta _createdAtMeta =
      const i0.VerificationMeta('createdAt');
  @override
  late final i0.GeneratedColumn<DateTime> createdAt =
      i0.GeneratedColumn<DateTime>('created_at', aliasedName, false,
          type: i0.DriftSqlType.dateTime,
          requiredDuringInsert: false,
          clientDefault: () => DateTime.now());
  static const i0.VerificationMeta _nameMeta =
      const i0.VerificationMeta('name');
  @override
  late final i0.GeneratedColumn<String> name = i0.GeneratedColumn<String>(
      'name', aliasedName, false,
      type: i0.DriftSqlType.string, requiredDuringInsert: true);
  static const i0.VerificationMeta _ownerIdMeta =
      const i0.VerificationMeta('ownerId');
  @override
  late final i0.GeneratedColumn<String> ownerId = i0.GeneratedColumn<String>(
      'owner_id', aliasedName, true,
      type: i0.DriftSqlType.string, requiredDuringInsert: false);
  @override
  List<i0.GeneratedColumn> get $columns => [id, createdAt, name, ownerId];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'lists';
  @override
  i0.VerificationContext validateIntegrity(i0.Insertable<i1.ListItem> instance,
      {bool isInserting = false}) {
    final context = i0.VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('created_at')) {
      context.handle(_createdAtMeta,
          createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta));
    }
    if (data.containsKey('name')) {
      context.handle(
          _nameMeta, name.isAcceptableOrUnknown(data['name']!, _nameMeta));
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('owner_id')) {
      context.handle(_ownerIdMeta,
          ownerId.isAcceptableOrUnknown(data['owner_id']!, _ownerIdMeta));
    }
    return context;
  }

  @override
  Set<i0.GeneratedColumn> get $primaryKey => const {};
  @override
  i1.ListItem map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return i1.ListItem(
      id: attachedDatabase.typeMapping
          .read(i0.DriftSqlType.string, data['${effectivePrefix}id'])!,
      createdAt: attachedDatabase.typeMapping.read(
          i0.DriftSqlType.dateTime, data['${effectivePrefix}created_at'])!,
      name: attachedDatabase.typeMapping
          .read(i0.DriftSqlType.string, data['${effectivePrefix}name'])!,
      ownerId: attachedDatabase.typeMapping
          .read(i0.DriftSqlType.string, data['${effectivePrefix}owner_id']),
    );
  }

  @override
  $ListItemsTable createAlias(String alias) {
    return $ListItemsTable(attachedDatabase, alias);
  }
}

class ListItem extends i0.DataClass implements i0.Insertable<i1.ListItem> {
  final String id;
  final DateTime createdAt;
  final String name;
  final String? ownerId;
  const ListItem(
      {required this.id,
      required this.createdAt,
      required this.name,
      this.ownerId});
  @override
  Map<String, i0.Expression> toColumns(bool nullToAbsent) {
    final map = <String, i0.Expression>{};
    map['id'] = i0.Variable<String>(id);
    map['created_at'] = i0.Variable<DateTime>(createdAt);
    map['name'] = i0.Variable<String>(name);
    if (!nullToAbsent || ownerId != null) {
      map['owner_id'] = i0.Variable<String>(ownerId);
    }
    return map;
  }

  i1.ListItemsCompanion toCompanion(bool nullToAbsent) {
    return i1.ListItemsCompanion(
      id: i0.Value(id),
      createdAt: i0.Value(createdAt),
      name: i0.Value(name),
      ownerId: ownerId == null && nullToAbsent
          ? const i0.Value.absent()
          : i0.Value(ownerId),
    );
  }

  factory ListItem.fromJson(Map<String, dynamic> json,
      {i0.ValueSerializer? serializer}) {
    serializer ??= i0.driftRuntimeOptions.defaultSerializer;
    return ListItem(
      id: serializer.fromJson<String>(json['id']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      name: serializer.fromJson<String>(json['name']),
      ownerId: serializer.fromJson<String?>(json['ownerId']),
    );
  }
  @override
  Map<String, dynamic> toJson({i0.ValueSerializer? serializer}) {
    serializer ??= i0.driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'name': serializer.toJson<String>(name),
      'ownerId': serializer.toJson<String?>(ownerId),
    };
  }

  i1.ListItem copyWith(
          {String? id,
          DateTime? createdAt,
          String? name,
          i0.Value<String?> ownerId = const i0.Value.absent()}) =>
      i1.ListItem(
        id: id ?? this.id,
        createdAt: createdAt ?? this.createdAt,
        name: name ?? this.name,
        ownerId: ownerId.present ? ownerId.value : this.ownerId,
      );
  ListItem copyWithCompanion(i1.ListItemsCompanion data) {
    return ListItem(
      id: data.id.present ? data.id.value : this.id,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      name: data.name.present ? data.name.value : this.name,
      ownerId: data.ownerId.present ? data.ownerId.value : this.ownerId,
    );
  }

  @override
  String toString() {
    return (StringBuffer('ListItem(')
          ..write('id: $id, ')
          ..write('createdAt: $createdAt, ')
          ..write('name: $name, ')
          ..write('ownerId: $ownerId')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, createdAt, name, ownerId);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is i1.ListItem &&
          other.id == this.id &&
          other.createdAt == this.createdAt &&
          other.name == this.name &&
          other.ownerId == this.ownerId);
}

class ListItemsCompanion extends i0.UpdateCompanion<i1.ListItem> {
  final i0.Value<String> id;
  final i0.Value<DateTime> createdAt;
  final i0.Value<String> name;
  final i0.Value<String?> ownerId;
  final i0.Value<int> rowid;
  const ListItemsCompanion({
    this.id = const i0.Value.absent(),
    this.createdAt = const i0.Value.absent(),
    this.name = const i0.Value.absent(),
    this.ownerId = const i0.Value.absent(),
    this.rowid = const i0.Value.absent(),
  });
  ListItemsCompanion.insert({
    this.id = const i0.Value.absent(),
    this.createdAt = const i0.Value.absent(),
    required String name,
    this.ownerId = const i0.Value.absent(),
    this.rowid = const i0.Value.absent(),
  }) : name = i0.Value(name);
  static i0.Insertable<i1.ListItem> custom({
    i0.Expression<String>? id,
    i0.Expression<DateTime>? createdAt,
    i0.Expression<String>? name,
    i0.Expression<String>? ownerId,
    i0.Expression<int>? rowid,
  }) {
    return i0.RawValuesInsertable({
      if (id != null) 'id': id,
      if (createdAt != null) 'created_at': createdAt,
      if (name != null) 'name': name,
      if (ownerId != null) 'owner_id': ownerId,
      if (rowid != null) 'rowid': rowid,
    });
  }

  i1.ListItemsCompanion copyWith(
      {i0.Value<String>? id,
      i0.Value<DateTime>? createdAt,
      i0.Value<String>? name,
      i0.Value<String?>? ownerId,
      i0.Value<int>? rowid}) {
    return i1.ListItemsCompanion(
      id: id ?? this.id,
      createdAt: createdAt ?? this.createdAt,
      name: name ?? this.name,
      ownerId: ownerId ?? this.ownerId,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, i0.Expression> toColumns(bool nullToAbsent) {
    final map = <String, i0.Expression>{};
    if (id.present) {
      map['id'] = i0.Variable<String>(id.value);
    }
    if (createdAt.present) {
      map['created_at'] = i0.Variable<DateTime>(createdAt.value);
    }
    if (name.present) {
      map['name'] = i0.Variable<String>(name.value);
    }
    if (ownerId.present) {
      map['owner_id'] = i0.Variable<String>(ownerId.value);
    }
    if (rowid.present) {
      map['rowid'] = i0.Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ListItemsCompanion(')
          ..write('id: $id, ')
          ..write('createdAt: $createdAt, ')
          ..write('name: $name, ')
          ..write('ownerId: $ownerId, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}
