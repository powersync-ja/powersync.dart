import 'package:drift/drift.dart';
import 'package:drift_sqlite_async/drift_sqlite_async.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:powersync/powersync.dart' show uuid;

import 'fts5.dart';
import 'powersync.dart';

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

final class ListItemWithStats {
  final ListItem self;
  final int completedCount;
  final int pendingCount;

  const ListItemWithStats(
    this.self,
    this.completedCount,
    this.pendingCount,
  );
}

@DriftDatabase(
  tables: [TodoItems, ListItems],
  include: {'queries.drift'},
)
class AppDatabase extends _$AppDatabase {
  AppDatabase(super.e);

  @override
  int get schemaVersion => 2;

  @override
  MigrationStrategy get migration {
    return MigrationStrategy(
      onCreate: (m) async {
        // We don't have to call createAll(), PowerSync instantiates the schema
        // for us. We can use the opportunity to create fts5 indexes though.
        await createFts5Tables(
          db: this,
          tableName: 'lists',
          columns: ['name'],
        );
        await createFts5Tables(
          db: this,
          tableName: 'todos',
          columns: ['description', 'list_id'],
        );
      },
      onUpgrade: (m, from, to) async {
        if (from == 1) {
          await createFts5Tables(
            db: this,
            tableName: 'todos',
            columns: ['description', 'list_id'],
          );
        }
      },
    );
  }

  Future<void> addTodoPhoto(String todoId, String photoId) async {
    await (update(todoItems)..where((t) => t.id.equals(todoId)))
        .write(TodoItemsCompanion(photoId: Value(photoId)));
  }

  Future<ListItem> findList(String id) {
    return (select(listItems)..where((t) => t.id.equals(id))).getSingle();
  }
}

final driftDatabase = Provider((ref) {
  return AppDatabase(DatabaseConnection.delayed(Future(() async {
    final database = await ref.read(powerSyncInstanceProvider.future);
    return SqliteAsyncDriftConnection(database);
  })));
});
