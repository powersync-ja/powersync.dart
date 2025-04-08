import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../app_config.dart';
import '../components/page_layout.dart';
import '../navigation.dart';
import '../powersync/database.dart';
import '../stores/items.dart';

@RoutePage()
final class ListsDetailsPage extends ConsumerWidget {
  final String list;

  const ListsDetailsPage({super.key, required this.list});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return PageLayout(
      title: const Text('Todo List'),
      showDrawer: false,
      content: _ItemsInListWidget(list: list),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          context.pushRoute(AddItemRoute(list: list));
        },
        tooltip: 'Add new item',
        child: const Icon(Icons.add),
      ),
    );
  }
}

final class _ItemsInListWidget extends ConsumerWidget {
  final String list;

  const _ItemsInListWidget({required this.list});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final items = ref.watch(itemsNotifierProvider(list));

    return items.maybeWhen(
      data: (items) => ListView(
        padding: const EdgeInsets.symmetric(vertical: 8.0),
        children: items.map((todo) {
          return _TodoItemWidget(
            todo: todo,
          );
        }).toList(),
      ),
      orElse: () => const CircularProgressIndicator(),
    );
  }
}

final class _TodoItemWidget extends ConsumerWidget {
  _TodoItemWidget({
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

  Future<void> deleteTodo(WidgetRef ref) async {
    await ref
        .read(itemsNotifierProvider(todo.listId).notifier)
        .deleteItem(todo);
  }

  Future<void> toggleTodo(WidgetRef ref) async {
    await ref
        .read(itemsNotifierProvider(todo.listId).notifier)
        .toggleTodo(todo);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ListTile(
      onTap: () => toggleTodo(ref),
      leading: Checkbox(
        value: todo.completed,
        onChanged: (_) => toggleTodo(ref),
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
            onPressed: () async => await deleteTodo(ref),
            tooltip: 'Delete Item',
          ),
          AppConfig.supabaseStorageBucket.isEmpty
              ? Container()
              : Placeholder(), //PhotoWidget(todo: todo),
        ],
      ),
    );
  }
}
