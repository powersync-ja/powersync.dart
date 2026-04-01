import 'package:flutter/material.dart';
import 'package:sqlite3/common.dart' as sqlite;

/// Stateless DataTable rendering results from a SQLite query
class ResultSetTable extends StatelessWidget {
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
