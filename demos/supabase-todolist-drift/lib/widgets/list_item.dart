import 'package:flutter/material.dart';
import 'package:supabase_todolist_drift/database.dart';
import 'package:supabase_todolist_drift/powersync.dart';

import 'todo_list_page.dart';

class ListItemWidget extends StatelessWidget {
  ListItemWidget({
    required this.list,
  }) : super(key: ObjectKey(list));

  final ListItemWithStats list;

  Future<void> delete() async {
    // Server will take care of deleting related todos
    await appDb.deleteList(list.self);
  }

  @override
  Widget build(BuildContext context) {
    viewList() {
      var navigator = Navigator.of(context);

      navigator.push(MaterialPageRoute(
          builder: (context) => TodoListPage(list: list.self)));
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
