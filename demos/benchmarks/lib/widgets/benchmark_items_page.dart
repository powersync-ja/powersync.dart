import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';

import 'benchmark_item_widget.dart';
import '../main.dart';
import '../models/benchmark_item.dart';
import '../powersync.dart';

var itemIndex = 1;

class BenchmarkItemsPage extends StatelessWidget {
  const BenchmarkItemsPage({super.key});

  @override
  Widget build(BuildContext context) {
    const content = BenchmarkItemsWidget();

    const page = MyHomePage(title: 'Benchmarks', content: content);
    return page;
  }
}

class BenchmarkItemsWidget extends StatefulWidget {
  const BenchmarkItemsWidget({super.key});

  @override
  State<StatefulWidget> createState() {
    return _BenchmarkItemsWidgetState();
  }
}

class _BenchmarkItemsWidgetState extends State<BenchmarkItemsWidget> {
  List<BenchmarkItem> _data = [];
  bool hasSynced = false;
  StreamSubscription? _subscription;
  StreamSubscription? _countSubscription;
  StreamSubscription? _syncStatusSubscription;
  String _latencyString = '0';
  int? count;

  _BenchmarkItemsWidgetState();

  @override
  void initState() {
    super.initState();
    _subscription = BenchmarkItem.watchGroupedItems().listen((data) {
      if (!context.mounted) {
        return;
      }

      // Latency is the same for all items in the group
      final latencies =
          data.map((e) => e.latency).where((e) => e != null).toList();
      final totalLatency = latencies.fold(0, (a, b) => a + b!.inMicroseconds);
      final averageLatencyMicros =
          latencies.isNotEmpty ? totalLatency / latencies.length : 0;
      final latencyString = (averageLatencyMicros / 1000.0).toStringAsFixed(1);

      setState(() {
        _data = data;
        _latencyString = latencyString;
      });
    });

    _countSubscription =
        db.watch('select count() as count from ps_oplog').listen((data) {
      if (!context.mounted) {
        return;
      }
      setState(() {
        count = data.first['count'];
      });
    });
    _syncStatusSubscription = db.statusStream.listen((status) {
      if (!context.mounted) {
        return;
      }
      setState(() {
        hasSynced = status.hasSynced ?? false;
      });
    });
  }

  @override
  void dispose() {
    super.dispose();
    _subscription?.cancel();
    _syncStatusSubscription?.cancel();
    _countSubscription?.cancel();
  }

  Future<void> createBatch(int n) async {
    var items = <String>[];
    for (var i = 1; i <= n; i++) {
      items.add('Batch Test $itemIndex/$i');
    }
    itemIndex += 1;
    await db.execute('''
      INSERT INTO
        benchmark_items(id, description, client_created_at)
      SELECT uuid(), e.value, datetime('now', 'subsecond') || 'Z'
      FROM json_each(?) e
      ''', [jsonEncode(items)]);
  }

  @override
  Widget build(BuildContext context) {
    Duration? syncDuration = timer.syncTime ?? timer.elapsed;
    if (!hasSynced) {
      return Center(
          child: Text(
              "Busy with sync... ${syncDuration.inMilliseconds}ms / $count operations"));
    }

    final clearButton = TextButton.icon(
        label: const Text('Delete all'),
        onPressed: () {
          BenchmarkItem.deleteAll();
        },
        icon: const Icon(Icons.delete));

    final resyncButton = TextButton.icon(
        label: const Text('Resync'),
        onPressed: () async {
          await resync();
        },
        icon: const Icon(Icons.sync));

    final create1 = TextButton.icon(
        label: const Text('+1'),
        onPressed: () async {
          await createBatch(1);
        },
        icon: const Icon(Icons.create));

    final create100 = TextButton.icon(
        label: const Text('+100'),
        onPressed: () async {
          await createBatch(100);
        },
        icon: const Icon(Icons.create));

    final create1000 = TextButton.icon(
        label: const Text('+1000'),
        onPressed: () async {
          await createBatch(1000);
        },
        icon: const Icon(Icons.create));

    var buttons = Padding(
      padding: const EdgeInsets.all(8.0),
      child: OverflowBar(
        alignment: MainAxisAlignment.end,
        spacing: 8.0,
        overflowSpacing: 8.0,
        children: <Widget>[
          Text(
              'First sync duration: ${syncDuration.inMilliseconds}ms / $count operations / ${_latencyString}ms latency'),
          create1,
          create100,
          create1000,
          resyncButton,
          clearButton,
        ],
      ),
    );
    return Column(children: [
      buttons,
      Expanded(
        child: ListView(
            padding: const EdgeInsets.symmetric(vertical: 8.0),
            children: _data.map((list) {
              return ListItemWidget(item: list);
            }).toList()),
      )
    ]);
  }
}
