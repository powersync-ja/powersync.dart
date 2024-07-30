import 'package:drift/drift.dart';
import 'package:powersync/powersync.dart'
    show PowerSyncDatabase, SyncStatus, uuid;
import 'package:drift_sqlite_async/drift_sqlite_async.dart';
import 'package:supabase_todolist_drift/powersync.dart';

part 'database.g.dart';

class TodoItems extends Table {
  @override
  String get tableName => 'todos';

  TextColumn get id => text().clientDefault(() => uuid.v4())();
  TextColumn get listId => text().named('list_id').references(ListItems, #id)();
  TextColumn get photoId => text().nullable().named('photo_id')();
  DateTimeColumn get createdAt => dateTime().nullable().named('created_at')();
  DateTimeColumn get completedAt =>
      dateTime().nullable().named('completed_at')();
  BoolColumn get completed => boolean().nullable()();
  TextColumn get description => text()();
  TextColumn get createdBy => text().nullable().named('created_by')();
  TextColumn get completedBy => text().nullable().named('completed_by')();
}

class ListItems extends Table {
  @override
  String get tableName => 'lists';

  TextColumn get id => text().clientDefault(() => uuid.v4())();
  DateTimeColumn get createdAt =>
      dateTime().named('created_at').clientDefault(() => DateTime.now())();
  TextColumn get name => text()();
  TextColumn get ownerId => text().nullable().named('owner_id')();
}

class ListItemWithStats {
  late ListItem self;
  int completedCount;
  int pendingCount;

  ListItemWithStats(
    this.self,
    this.completedCount,
    this.pendingCount,
  );
}

@DriftDatabase(tables: [TodoItems, ListItems], include: {'queries.drift'})
class AppDatabase extends _$AppDatabase {
  AppDatabase(PowerSyncDatabase db) : super(SqliteAsyncDriftConnection(db));

  @override
  int get schemaVersion => 1;

  Stream<List<ListItem>> watchLists() {
    return (select(listItems)
          ..orderBy([(l) => OrderingTerm(expression: l.createdAt)]))
        .watch();
  }

  Stream<List<ListItemWithStats>> watchListsWithStats() {
    return listsWithStats().watch();
  }

  Future<ListItem> createList(String name) async {
    return into(listItems).insertReturning(
        ListItemsCompanion.insert(name: name, ownerId: Value(getUserId())));
  }

  Future<void> deleteList(ListItem list) async {
    await (delete(listItems)..where((t) => t.id.equals(list.id))).go();
  }

  Stream<List<TodoItem>> watchTodoItems(ListItem list) {
    return (select(todoItems)
          ..where((t) => t.listId.equals(list.id))
          ..orderBy([(t) => OrderingTerm(expression: t.createdAt)]))
        .watch();
  }

  Future<void> deleteTodo(TodoItem todo) async {
    await (delete(todoItems)..where((t) => t.id.equals(todo.id))).go();
  }

  Future<TodoItem> addTodo(ListItem list, String description) async {
    return into(todoItems).insertReturning(TodoItemsCompanion.insert(
        listId: list.id,
        description: description,
        completed: const Value(false),
        createdBy: Value(getUserId())));
  }

  Future<void> toggleTodo(TodoItem todo) async {
    if (todo.completed != true) {
      await (update(todoItems)..where((t) => t.id.equals(todo.id))).write(
          TodoItemsCompanion(
              completed: const Value(true),
              completedAt: Value(DateTime.now()),
              completedBy: Value(getUserId())));
    } else {
      await (update(todoItems)..where((t) => t.id.equals(todo.id))).write(
          const TodoItemsCompanion(
              completed: Value(false),
              completedAt: Value.absent(),
              completedBy: Value.absent()));
    }
  }

  Future<void> addTodoPhoto(String todoId, String photoId) async {
    await (update(todoItems)..where((t) => t.id.equals(todoId)))
        .write(TodoItemsCompanion(photoId: Value(photoId)));
  }

  Future<ListItem> findList(String id) {
    return (select(listItems)..where((t) => t.id.equals(id))).getSingle();
  }
}
