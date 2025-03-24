import 'package:flutter/material.dart';

import './status_app_bar.dart';
import './todo_item_dialog.dart';
import './todo_item_widget.dart';
import '../models/todo_list.dart';

void _showAddDialog(BuildContext context, TodoList list) async {
  return showDialog<void>(
    context: context,
    barrierDismissible: false, // user must tap button!
    builder: (BuildContext context) {
      return TodoItemDialog(list: list);
    },
  );
}

class TodoListPage extends StatelessWidget {
  final TodoList list;

  const TodoListPage({super.key, required this.list});

  @override
  Widget build(BuildContext context) {
    final button = FloatingActionButton(
      onPressed: () {
        _showAddDialog(context, list);
      },
      tooltip: 'Add Item',
      child: const Icon(Icons.add),
    );

    return Scaffold(
        appBar: StatusAppBar(title: Text(list.name)),
        floatingActionButton: button,
        body: TodoListWidget(list: list));
  }
}

class TodoListWidget extends StatelessWidget {
  final TodoList list;

  const TodoListWidget({super.key, required this.list});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder(
      stream: list.watchItems(),
      builder: (context, snapshot) {
        final items = snapshot.data ?? const [];

        return ListView(
          padding: const EdgeInsets.symmetric(vertical: 8.0),
          children: items.map((todo) {
            return TodoItemWidget(todo: todo);
          }).toList(),
        );
      },
    );
  }
}
