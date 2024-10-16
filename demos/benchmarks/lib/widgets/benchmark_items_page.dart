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

    final addButton = FloatingActionButton(
      onPressed: () {
        BenchmarkItem.create('Latency test ${itemIndex++}');
      },
      tooltip: 'Create Item',
      child: const Icon(Icons.add),
    );

    final page = MyHomePage(
      title: 'Benchmarks',
      content: content,
      floatingActionButton: addButton,
    );
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
  int? count;

  _BenchmarkItemsWidgetState();

  @override
  void initState() {
    super.initState();
    final stream = BenchmarkItem.watchItems();
    _subscription = stream.listen((data) {
      if (!context.mounted) {
        return;
      }
      setState(() {
        _data = data;
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

    final create100 = TextButton.icon(
        label: const Text('Create 100'),
        onPressed: () async {
          var items = <String>[];
          for (var i = 1; i <= 100; i++) {
            items.add('Batch Test $itemIndex/$i');
          }
          itemIndex += 1;
          await db.execute('''
      INSERT INTO
        benchmark_items(id, description, client_created_at)
      SELECT uuid(), e.value, datetime('now', 'subsecond') || 'Z'
      FROM json_each(?) e
      ''', [jsonEncode(items)]);
        },
        icon: const Icon(Icons.create));

    final create1000 = TextButton.icon(
        label: const Text('Create 1000'),
        onPressed: () async {
          var items = <String>[];
          for (var i = 1; i <= 1000; i++) {
            items.add('Batch Test $itemIndex/$i');
          }
          itemIndex += 1;
          await db.execute('''
      INSERT INTO
        benchmark_items(id, description, client_created_at)
      SELECT uuid(), e.value, datetime('now', 'subsecond') || 'Z'
      FROM json_each(?) e
      ''', [jsonEncode(items)]);
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
              'First sync duration: ${syncDuration.inMilliseconds}ms / $count operations'),
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
