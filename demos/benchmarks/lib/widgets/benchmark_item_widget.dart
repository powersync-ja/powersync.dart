import 'package:flutter/material.dart';

import '../models/benchmark_item.dart';

class ListItemWidget extends StatelessWidget {
  ListItemWidget({
    required this.item,
  }) : super(key: ObjectKey(item.id));

  final BenchmarkItem item;

  Future<void> delete() async {
    await item.delete();
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          ListTile(
              leading: const Icon(Icons.list), title: Text(item.description)),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: <Widget>[
              IconButton(
                iconSize: 30,
                icon: const Icon(
                  Icons.delete,
                  color: Colors.red,
                ),
                tooltip: 'Delete Item',
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
