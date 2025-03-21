import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:powersync/powersync.dart';
import 'package:supabase_todolist_drift/powersync.dart';

import 'list_item.dart';
import 'list_item_dialog.dart';
import '../main.dart';

void _showAddDialog(BuildContext context) async {
  return showDialog<void>(
    context: context,
    barrierDismissible: false, // user must tap button!
    builder: (BuildContext context) {
      return const ListItemDialog();
    },
  );
}

class ListsPage extends StatelessWidget {
  const ListsPage({super.key});

  @override
  Widget build(BuildContext context) {
    const content = ListsWidget();

    final button = FloatingActionButton(
      onPressed: () {
        _showAddDialog(context);
      },
      tooltip: 'Create List',
      child: const Icon(Icons.add),
    );

    final page = MyHomePage(
      title: 'Todo Lists',
      content: content,
      floatingActionButton: button,
    );
    return page;
  }
}

final _listsWithStats = StreamProvider((ref) {
  final database = ref.watch(driftDatabase);
  return database.listsWithStats().watch();
});

final class ListsWidget extends ConsumerWidget {
  const ListsWidget({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lists = ref.watch(_listsWithStats);
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
