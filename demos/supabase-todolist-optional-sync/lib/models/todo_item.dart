import 'package:powersync_flutter_supabase_todolist_optional_sync_demo/models/schema.dart';

import '../powersync.dart';
import 'package:powersync/sqlite3_common.dart' as sqlite;

/// TodoItem represents a result row of a query on "todos".
///
/// This class is immutable - methods on this class do not modify the instance
/// directly. Instead, watch or re-query the data to get the updated item.
class TodoItem {
  final String id;
  final String description;
  final bool completed;

  TodoItem({
    required this.id,
    required this.description,
    required this.completed,
  });

  factory TodoItem.fromRow(sqlite.Row row) {
    return TodoItem(
        id: row['id'],
        description: row['description'],
        completed: row['completed'] == 1);
  }

  Future<void> toggle() async {
    if (completed) {
      await db.execute(
          'UPDATE $todosTable SET completed = FALSE, completed_by = NULL, completed_at = NULL WHERE id = ?',
          [id]);
    } else {
      await db.execute(
          'UPDATE $todosTable SET completed = TRUE, completed_by = ?, completed_at = datetime() WHERE id = ?',
          [getUserId(), id]);
    }
  }

  Future<void> delete() async {
    await db.execute('DELETE FROM $todosTable WHERE id = ?', [id]);
  }
}
