import 'package:flutter/material.dart';
import 'package:powersync/sqlite3_common.dart' as sqlite;

/// Stateless DataTable rendering results from a SQLite query
class ResultSetTable extends StatelessWidget {
  const ResultSetTable({super.key, this.data});

  final sqlite.ResultSet? data;

  @override
  Widget build(BuildContext context) {
    if (data == null) {
      return const Text('Loading...');
    }
    final table = DataTable(
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
        if (data!.isEmpty)
          DataRow(
            cells: data!.columnNames.indexed
                .map((c) => c.$1 == 0
                    ? const DataCell(Text('Empty'), placeholder: true)
                    : const DataCell(Text('')))
                .toList(),
          ),
        for (var row in data!.rows)
          DataRow(
            cells: <DataCell>[
              for (var cell in row) DataCell(Text((cell ?? '').toString())),
            ],
          ),
      ],
    );

    return table;
  }
}
