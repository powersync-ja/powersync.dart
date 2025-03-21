import 'package:flutter/material.dart';
import 'package:powersync/powersync.dart';
import 'package:powersync_flutter_demo/powersync.dart';

import './list_item.dart';
import './list_item_dialog.dart';
import '../main.dart';
import '../models/todo_list.dart';

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

class ListsWidget extends StatelessWidget {
  const ListsWidget({super.key});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder(
      future: db.waitForFirstSync(priority: _listsPriority),
      builder: (context, snapshot) {
        return switch (snapshot.connectionState) {
          ConnectionState.done => StreamBuilder(
              stream: TodoList.watchListsWithStats(),
              builder: (context, snapshot) {
                final items = snapshot.data ?? const [];

                return ListView(
                  padding: const EdgeInsets.symmetric(vertical: 8.0),
                  children: items.map((list) {
                    return ListItemWidget(list: list);
                  }).toList(),
                );
              },
            ),
          // waitForFirstSync() did not complete yet
          _ => const Text('Busy with sync...'),
        };
      },
    );
  }

  static final _listsPriority = BucketPriority(1);
}
