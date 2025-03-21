import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:powersync/sqlite3_common.dart' as sqlite;
import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'resultset_table.dart';
import '../powersync.dart';

part 'query_widget.g.dart';

@riverpod
Stream<sqlite.ResultSet> _watch(Ref ref, String sql) async* {
  final db = await ref.read(initializePowerSyncProvider.future);
  yield* db.watch(sql);
}

final class QueryWidget extends HookConsumerWidget {
  final String defaultQuery;

  const QueryWidget({super.key, required this.defaultQuery});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final query = useState(defaultQuery);
    final controller = useTextEditingController();
    final rows = ref.watch(_watchProvider(query.value));

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: TextField(
            controller: controller,
            onEditingComplete: () {
              query.value = controller.text;
            },
            decoration: InputDecoration(
              isDense: false,
              border: const OutlineInputBorder(),
              labelText: 'Query',
              errorText: rows.error?.toString(),
            ),
          ),
        ),
        Expanded(
            child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: SingleChildScrollView(
            scrollDirection: Axis.vertical,
            child: ResultSetTable(data: rows.value),
          ),
        ))
      ],
    );
  }
}
