import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:powersync/sqlite3_common.dart' as sqlite;
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../components/page_layout.dart';
import '../powersync/powersync.dart';
import '../powersync/schema.dart';

part 'sql_console.g.dart';

@riverpod
Stream<sqlite.ResultSet> _watch(Ref ref, String sql) async* {
  final db = await ref.read(powerSyncInstanceProvider.future);
  yield* db.watch(sql);
}

@RoutePage()
final class SqlConsolePage extends HookConsumerWidget {
  const SqlConsolePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final query = useState('SELECT * FROM $todosTable');
    final controller = useTextEditingController(text: query.value);
    final rows = ref.watch(_watchProvider(query.value));

    return PageLayout(
      showDrawer: false,
      content: Column(
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
          if (rows case AsyncData(:final value))
            Expanded(
                child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: SingleChildScrollView(
                scrollDirection: Axis.vertical,
                child: ResultSetTable(data: value),
              ),
            ))
        ],
      ),
    );
  }
}

/// Stateless DataTable rendering results from a SQLite query
final class ResultSetTable extends StatelessWidget {
  const ResultSetTable({super.key, this.data});

  final sqlite.ResultSet? data;

  @override
  Widget build(BuildContext context) {
    if (data == null) {
      return const Text('Loading...');
    } else if (data!.isEmpty) {
      return const Text('Empty');
    }
    return DataTable(
      columns: <DataColumn>[
        for (var column in data!.columnNames)
          DataColumn(
            label: Expanded(
              child: Text(
                column,
                style: const TextStyle(fontStyle: FontStyle.italic),
              ),
            ),
          ),
      ],
      rows: <DataRow>[
        for (var row in data!.rows)
          DataRow(
            cells: <DataCell>[
              for (var cell in row) DataCell(Text((cell ?? '').toString())),
            ],
          ),
      ],
    );
  }
}
