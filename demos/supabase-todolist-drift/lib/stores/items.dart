import 'package:drift/drift.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../powersync/attachments/queue.dart';
import '../powersync/database.dart';
import '../supabase.dart';

part 'items.g.dart';

@riverpod
final class ItemsNotifier extends _$ItemsNotifier {
  @override
  Stream<List<TodoItem>> build(String list) {
    final database = ref.watch(driftDatabase);
    final query = database.select(database.todoItems)
      ..where((row) => row.listId.equals(list))
      ..orderBy([(t) => OrderingTerm(expression: t.createdAt)]);
    return query.watch();
  }

  Future<void> toggleTodo(TodoItem todo) async {
    final db = ref.read(driftDatabase);
    final userId = ref.read(userIdProvider);

    final stmt = db.update(db.todoItems)..where((t) => t.id.equals(todo.id));

    if (todo.completed != true) {
      await stmt.write(
        TodoItemsCompanion(
            completed: const Value(true),
            completedAt: Value(DateTime.now()),
            completedBy: Value(userId)),
      );
    } else {
      await stmt.write(const TodoItemsCompanion(completed: Value(false)));
    }
  }

  Future<void> deleteItem(TodoItem item) async {
    final db = ref.read(driftDatabase);
    if (item.photoId case final photo?) {
      final queue = await ref.read(attachmentQueueProvider.future);
      queue.deleteFile(photo);
    }

    await (db.delete(db.todoItems)..where((t) => t.id.equals(item.id))).go();
  }

  Future<void> addItem(String description) async {
    final db = ref.read(driftDatabase);
    final userId = ref.read(userIdProvider);

    await db.into(db.todoItems).insertReturning(
          TodoItemsCompanion.insert(
            listId: list,
            description: description,
            completed: const Value(false),
            createdBy: Value(userId),
          ),
        );
  }
}
