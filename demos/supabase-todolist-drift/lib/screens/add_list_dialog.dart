import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../stores/lists.dart';

@RoutePage(name: 'AddListRoute')
final class AddListDialog extends HookConsumerWidget {
  const AddListDialog({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final textController = useTextEditingController();

    Future<void> add() async {
      await ref
          .read(listsNotifierProvider.notifier)
          .createNewList(textController.text);
      if (context.mounted) {
        context.pop();
      }
    }

    return AlertDialog(
      title: const Text('Add a new list'),
      content: TextField(
        controller: textController,
        decoration: const InputDecoration(hintText: 'List name'),
        onSubmitted: (value) async {
          await add();
        },
        autofocus: true,
      ),
      actions: <Widget>[
        OutlinedButton(
          child: const Text('Cancel'),
          onPressed: () {
            textController.clear();
            context.pop();
          },
        ),
        ElevatedButton(
          child: const Text('Create'),
          onPressed: () async {
            await add();
          },
        ),
      ],
    );
  }
}
