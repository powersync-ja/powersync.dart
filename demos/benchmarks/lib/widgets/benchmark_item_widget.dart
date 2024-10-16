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

    String subtitle = item.latency == null
        ? 'Syncing...'
        : 'Sync latency: $latency / upload: $uploadLatency';
    return Card(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          ListTile(
            leading: const Icon(Icons.timer),
            title: Text(item.description),
            subtitle: Text(subtitle),
          ),
        ],
      ),
    );
  }
}
