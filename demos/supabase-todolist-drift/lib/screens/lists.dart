import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:powersync/powersync.dart' hide Column;

import '../components/page_layout.dart';
import '../navigation.dart';
import '../powersync/database.dart';
import '../powersync/powersync.dart';
import '../stores/lists.dart';

@RoutePage()
final class ListsPage extends ConsumerWidget {
  const ListsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return PageLayout(
      title: const Text('Todo Lists'),
      content: const _ListsWidget(),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          context.pushRoute(const AddListRoute());
        },
        tooltip: 'Create List',
        child: const Icon(Icons.add),
      ),
    );
  }
}

final class _ListsWidget extends ConsumerWidget {
  const _ListsWidget();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lists = ref.watch(listsNotifierProvider);
    final didSync = ref.watch(didCompleteSyncProvider(BucketPriority(1)));

    if (!didSync) {
      return const Text('Busy with sync...');
    }

    return lists.map(
      data: (data) {
        return ListView(
          padding: const EdgeInsets.symmetric(vertical: 8.0),
          children: data.value.map((list) {
            return ListItemWidget(list: list);
          }).toList(),
        );
      },
      error: (_) => const Text('Error loading lists'),
      loading: (_) => const CircularProgressIndicator(),
    );
  }
}

class ListItemWidget extends ConsumerWidget {
  ListItemWidget({
    required this.list,
  }) : super(key: ObjectKey(list));

  final ListItemWithStats list;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    Future<void> delete() async {
      await ref.read(listsNotifierProvider.notifier).deleteList(list.self.id);
    }

    void viewList() {
      context.pushRoute(ListsDetailsRoute(list: list.self.id));
    }

    final subtext =
        '${list.pendingCount} pending, ${list.completedCount} completed';

    return Card(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          ListTile(
              onTap: viewList,
              leading: const Icon(Icons.list),
              title: Text(list.self.name),
              subtitle: Text(subtext)),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: <Widget>[
              IconButton(
                iconSize: 30,
                icon: const Icon(
                  Icons.delete,
                  color: Colors.red,
                ),
                tooltip: 'Delete List',
                alignment: Alignment.centerRight,
                onPressed: delete,
              ),
              const SizedBox(width: 8),
            ],
          ),
        ],
      ),
    );
  }
}
