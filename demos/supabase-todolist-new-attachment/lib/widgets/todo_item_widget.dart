import 'package:flutter/material.dart';
import 'package:powersync_flutter_demo_new/app_config.dart';
import 'package:powersync_flutter_demo_new/attachments/photo_widget.dart';
import 'package:powersync_flutter_demo_new/attachments/queue.dart';

import '../models/todo_item.dart';

class TodoItemWidget extends StatelessWidget {
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

  Future<void> deleteTodo(TodoItem todo) async {
    if (todo.photoId != null) {
      print('deleteTodo: ${todo.photoId}');
      
      await attachmentQueue.deleteFile(
        attachmentId: todo.photoId!,
        updateHook: (context, attachment) async {
          // await context.execute("UPDATE todos SET photo_id = NULL WHERE id = ?", [todo.id]);
        },
      );
    }
    await todo.delete();
  }

  @override
  Widget build(BuildContext context) {
    return ListTile(
        onTap: todo.toggle,
        leading: Checkbox(
          value: todo.completed,
          onChanged: (_) {
            todo.toggle();
          },
        ),
        title: Row(
          children: <Widget>[
            Expanded(
                child: Text(todo.description,
                    style: _getTextStyle(todo.completed))),
            IconButton(
              iconSize: 30,
              icon: const Icon(
                Icons.delete,
                color: Colors.red,
              ),
              alignment: Alignment.centerRight,
              onPressed: () async => await deleteTodo(todo),
              tooltip: 'Delete Item',
            ),
            AppConfig.supabaseStorageBucket.isEmpty
                ? Container()
                : PhotoWidget(todo: todo),
          ],
        ));
  }
}
