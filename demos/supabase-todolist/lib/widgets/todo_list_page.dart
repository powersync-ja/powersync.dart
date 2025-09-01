import 'package:flutter/material.dart';
import 'package:powersync/powersync.dart';

import '../app_config.dart';
import '../powersync.dart';
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
      body: AppConfig.hasSyncStreams
          ? _SyncStreamTodoListWidget(list: list)
          : TodoListWidget(list: list),
    );
  }
}

class TodoListWidget extends StatelessWidget {
  final TodoList list;

  const TodoListWidget({super.key, required this.list});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder(
      stream: TodoList.watchSyncStatus().map((e) => e.hasSynced),
      initialData: db.currentStatus.hasSynced,
      builder: (context, snapshot) {
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
      },
    );
  }
}

class _SyncStreamTodoListWidget extends StatefulWidget {
  final TodoList list;

  const _SyncStreamTodoListWidget({required this.list});

  @override
  State<_SyncStreamTodoListWidget> createState() => _SyncStreamTodosState();
}

class _SyncStreamTodosState extends State<_SyncStreamTodoListWidget> {
  SyncStreamSubscription? _listSubscription;

  void _subscribe(String listId) {
    db
        .syncStream('todos', {'list': listId})
        .subscribe(ttl: const Duration(hours: 1))
        .then((sub) {
          if (mounted && widget.list.id == listId) {
            setState(() {
              _listSubscription = sub;
            });
          } else {
            sub.unsubscribe();
          }
        });
  }

  @override
  void initState() {
    super.initState();
    _subscribe(widget.list.id);
  }

  @override
  void didUpdateWidget(covariant _SyncStreamTodoListWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    _subscribe(widget.list.id);
  }

  @override
  void dispose() {
    super.dispose();
    _listSubscription?.unsubscribe();
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder(
      stream: db.statusStream,
      initialData: db.currentStatus,
      builder: (context, snapshot) {
        final hasSynced = switch (_listSubscription) {
              null => null,
              final sub => snapshot.requireData.statusFor(sub),
            }
                ?.subscription
                .hasSynced ??
            false;

        if (!hasSynced) {
          return const CircularProgressIndicator();
        } else {
          return StreamBuilder(
            stream: widget.list.watchItems(),
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
      },
    );
  }
}
