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
    String latency =
        item.latency != null ? '${item.latency!.inMilliseconds}ms' : '';

    String uploadLatency = item.uploadLatency != null
        ? '${item.uploadLatency!.inMilliseconds}ms'
        : '';

    String subtitle =
        '$latency / $uploadLatency / ${item.serverCreatedAt?.toIso8601String() ?? ''}';
    return Card(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          ListTile(
            leading: const Icon(Icons.list),
            title: Text(item.description),
            subtitle: Text(subtitle),
          ),
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
