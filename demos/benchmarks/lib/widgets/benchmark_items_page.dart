import 'dart:async';

import 'package:flutter/material.dart';

import 'benchmark_item_widget.dart';
import '../main.dart';
import '../models/benchmark_item.dart';
import '../powersync.dart';

class BenchmarkItemsPage extends StatelessWidget {
  const BenchmarkItemsPage({super.key});

  @override
  Widget build(BuildContext context) {
    const content = BenchmarkItemsWidget();

    final button = FloatingActionButton(
      onPressed: () {
        BenchmarkItem.create('Benchmarks');
      },
      tooltip: 'Create Item',
      child: const Icon(Icons.add),
    );

    final page = MyHomePage(
      title: 'Benchmarks',
      content: content,
      floatingActionButton: button,
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
  StreamSubscription? _syncStatusSubscription;

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
  }

  @override
  Widget build(BuildContext context) {
    return !hasSynced
        ? const Text("Busy with sync...")
        : ListView(
            padding: const EdgeInsets.symmetric(vertical: 8.0),
            children: _data.map((list) {
              return ListItemWidget(item: list);
            }).toList(),
          );
  }
}
