import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:supabase_todolist_drift/powersync.dart';

final class NewListDialog extends HookConsumerWidget {
  const NewListDialog({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final textController = useTextEditingController();

    Future<void> add() async {
      await ref
          .read(driftDatabase)
          .createList(textController.text, ref.read(userIdProvider));
    }

    return AlertDialog(
      title: const Text('Add a new list'),
      content: TextField(
        controller: textController,
        decoration: const InputDecoration(hintText: 'List name'),
        onSubmitted: (value) async {
          Navigator.of(context).pop();
          await add();
        },
        autofocus: true,
      ),
      actions: <Widget>[
        OutlinedButton(
          child: const Text('Cancel'),
          onPressed: () {
            textController.clear();
            Navigator.of(context).pop();
          },
        ),
        ElevatedButton(
          child: const Text('Create'),
          onPressed: () async {
            Navigator.of(context).pop();
            await add();
          },
        ),
      ],
    );
  }
}
