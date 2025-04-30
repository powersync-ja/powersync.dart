import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../stores/items.dart';

@RoutePage(name: 'AddItemRoute')
final class AddItemDialog extends HookConsumerWidget {
  final String list;

  const AddItemDialog({super.key, required this.list});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = useTextEditingController();

    Future<void> add() async {
      await ref
          .read(itemsNotifierProvider(list).notifier)
          .addItem(controller.text);
      if (context.mounted) {
        context.pop();
      }
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
