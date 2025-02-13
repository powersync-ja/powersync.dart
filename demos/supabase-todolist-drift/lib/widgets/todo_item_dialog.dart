import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_todolist_drift/database.dart';
import 'package:supabase_todolist_drift/powersync.dart';

class TodoItemDialog extends ConsumerStatefulWidget {
  final ListItem list;

  const TodoItemDialog({super.key, required this.list});

  @override
  ConsumerState<TodoItemDialog> createState() {
    return _TodoItemDialogState();
  }
}

class _TodoItemDialogState extends ConsumerState<TodoItemDialog> {
  final TextEditingController _textFieldController = TextEditingController();

  _TodoItemDialogState();

  @override
  void initState() {
    super.initState();
  }

  @override
  void dispose() {
    super.dispose();
    _textFieldController.dispose();
  }

  Future<void> add() async {
    Navigator.of(context).pop();
    final db = ref.read(driftDatabase);

    await db.addTodo(
        widget.list, _textFieldController.text, ref.read(userIdProvider));
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Add a new todo item'),
      content: TextField(
        controller: _textFieldController,
        decoration: const InputDecoration(hintText: 'Type your new todo'),
        onSubmitted: (value) {
          add();
        },
        autofocus: true,
      ),
      actions: <Widget>[
        OutlinedButton(
          child: const Text('Cancel'),
          onPressed: () {
            _textFieldController.clear();
            Navigator.of(context).pop();
          },
        ),
        ElevatedButton(
          onPressed: add,
          child: const Text('Add'),
        ),
      ],
    );
  }
}
