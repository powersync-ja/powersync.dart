import 'package:flutter/material.dart';

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
              onPressed: todo.delete,
              tooltip: 'Delete Item',
            )
          ],
        ));
  }
}
