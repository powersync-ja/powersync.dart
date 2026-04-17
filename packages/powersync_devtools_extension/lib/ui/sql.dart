import 'package:devtools_app_shared/ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:sqlite3/common.dart' hide Row;

import '../state/databases.dart';

final _sql = StateProvider<String>((ref) {
  // Reset SQL when the selected database changes.
  ref.watch(selectedDatabase);
  return '';
});

final class _ResultsNotifier extends Notifier<AsyncValue<ResultSet?>> {
  @override
  AsyncValue<ResultSet?> build() {
    ref.watch(selectedDatabase);

    return .data(null);
  }

  void runQuery() async {
    final db = ref.read(selectedDatabase);
    if (state.isLoading || db == null) {
      return;
    }

    final sql = ref.read(_sql);
    state = .loading();

    state = await AsyncValue.guard(() async {
      return await db.getAll(sql);
    });
  }
}

final _results = NotifierProvider(_ResultsNotifier.new);

final definedTables = FutureProvider.autoDispose<List<String>>((ref) async {
  final db = ref.watch(selectedDatabase);
  if (db == null) {
    return const [];
  }

  final serializedSchema = await db.serializedSchema();
  final foundTables = <String>[];

  for (final table
      in (serializedSchema['tables'] as List).cast<Map<String, Object?>>()) {
    foundTables.add(table['name'] as String);
  }

  for (final table
      in (serializedSchema['raw_tables'] as List)
          .cast<Map<String, Object?>>()) {
    foundTables.add((table['table_name'] ?? table['name']) as String);
  }

  return foundTables;
});

final class SqlPage extends ConsumerWidget {
  const SqlPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return const Column(
      crossAxisAlignment: .stretch,
      children: [
        Padding(padding: EdgeInsets.all(8), child: _QueryWidget()),
        Expanded(
          child: Padding(
            padding: EdgeInsets.only(top: 16),
            child: _ResultsWidget(),
          ),
        ),
      ],
    );
  }
}

final class _QueryWidget extends HookConsumerWidget {
  const _QueryWidget();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sql = ref.watch(_sql);
    final controller = useTextEditingController(text: sql);
    final isLoading = ref.watch(_results).isLoading;
    final disabled = isLoading || sql.trim().isEmpty;
    final tables = ref.watch(definedTables);

    ref.listen(_sql, (_, sql) => controller.text = sql);

    ButtonGroupItemData selectFromTable(String table) {
      return ButtonGroupItemData(
        label: table,
        onPressed: () {
          ref.read(_sql.notifier).state = 'SELECT * FROM $table';
          ref.read(_results.notifier).runQuery();
        },
      );
    }

    return RoundedOutlinedBorder(
      child: Padding(
        padding: const EdgeInsets.all(8.0),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: controller,
                    decoration: InputDecoration(label: Text('SQL')),
                    onChanged: (contents) {
                      ref.read(_sql.notifier).state = contents;
                    },
                  ),
                ),
                VerticalDivider(),
                DevToolsButton(
                  onPressed: disabled
                      ? null
                      : () {
                          ref.read(_results.notifier).runQuery();
                        },
                  label: 'Execute',
                  icon: Icons.play_arrow,
                ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Row(
                children: [
                  Text('Or select from: '),
                  Expanded(
                    child: SingleChildScrollView(
                      scrollDirection: .horizontal,
                      child: RoundedButtonGroup(
                        items: [
                          selectFromTable('ps_crud'),
                          selectFromTable('ps_oplog'),
                          selectFromTable('ps_untyped'),
                          selectFromTable('ps_buckets'),
                          if (tables.value case final foundTables?) ...[
                            for (final table in foundTables)
                              selectFromTable(table),
                          ],
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

final class _ResultsWidget extends ConsumerWidget {
  const _ResultsWidget();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final results = ref.watch(_results);

    switch (results) {
      case AsyncLoading<ResultSet?>():
        return Center(child: CircularProgressIndicator());
      case AsyncData<ResultSet?>(:final value):
        if (value == null) {
          return const SizedBox.shrink();
        }

        return DevToolsAreaPane(
          header: AreaPaneHeader(title: Text('Query results')),
          child: PaginatedDataTable(
            showEmptyRows: false,
            columns: [
              for (final column in value.columnNames)
                DataColumn(label: Text(column)),
            ],
            source: ResultSetDataSource(value),
          ),
        );

      case AsyncError<ResultSet?>(:final error, :final stackTrace):
        return SingleChildScrollView(
          child: SelectableText('Error: $error\n$stackTrace'),
        );
    }
  }
}

final class ResultSetDataSource extends DataTableSource {
  final ResultSet resultSet;

  ResultSetDataSource(this.resultSet);

  @override
  DataRow? getRow(int index) {
    if (index >= rowCount) return null;

    final row = resultSet.rows[index];
    return DataRow(
      cells: <DataCell>[
        for (var cell in row) DataCell(Text((cell ?? '').toString())),
      ],
    );
  }

  @override
  bool get isRowCountApproximate => false;

  @override
  int get rowCount => resultSet.length;

  @override
  int get selectedRowCount => 0;
}
