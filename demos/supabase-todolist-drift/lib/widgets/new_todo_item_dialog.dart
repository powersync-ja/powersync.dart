import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:supabase_todolist_drift/powersync/database.dart';
import 'package:supabase_todolist_drift/powersync.dart';

final class NewTodoItemDialog extends HookConsumerWidget {
  final ListItem list;

  const NewTodoItemDialog({super.key, required this.list});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = useTextEditingController();

    Future<void> add() async {
      Navigator.of(context).pop();
      final db = ref.read(driftDatabase);

      await db.addTodo(list, controller.text, ref.read(userIdProvider));
    }

    return AlertDialog(
      title: const Text('Add a new todo item'),
      content: TextField(
        controller: controller,
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
            controller.clear();
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
