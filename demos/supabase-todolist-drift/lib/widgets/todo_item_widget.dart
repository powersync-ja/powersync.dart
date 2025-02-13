import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_todolist_drift/app_config.dart';
import 'package:supabase_todolist_drift/attachments/photo_widget.dart';
import 'package:supabase_todolist_drift/attachments/queue.dart';
import 'package:supabase_todolist_drift/database.dart';
import 'package:supabase_todolist_drift/powersync.dart';

class TodoItemWidget extends ConsumerWidget {
  TodoItemWidget({
    required this.todo,
  }) : super(key: ObjectKey(todo.id));

  final TodoItem todo;

  TextStyle? _getTextStyle(bool checked) {
    if (!checked) return null;

    return const TextStyle(
      color: Colors.black54,
      decoration: TextDecoration.lineThrough,
    );
  }

  Future<void> deleteTodo(AppDatabase db, TodoItem todo) async {
    if (todo.photoId != null) {
      attachmentQueue.deleteFile(todo.photoId!);
    }
    await db.deleteTodo(todo);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final appDb = ref.watch(driftDatabase);

    return ListTile(
        onTap: () => appDb.toggleTodo(todo, ref.read(userIdProvider)),
        leading: Checkbox(
          value: todo.completed,
          onChanged: (_) {
            appDb.toggleTodo(todo, ref.read(userIdProvider));
          },
        ),
        title: Row(
          children: <Widget>[
            Expanded(
                child: Text(todo.description,
                    style: _getTextStyle(todo.completed == true))),
            IconButton(
              iconSize: 30,
              icon: const Icon(
                Icons.delete,
                color: Colors.red,
              ),
              alignment: Alignment.centerRight,
              onPressed: () async => await deleteTodo(appDb, todo),
              tooltip: 'Delete Item',
            ),
            AppConfig.supabaseStorageBucket.isEmpty
                ? Container()
                : PhotoWidget(todo: todo),
          ],
        ));
  }
}
