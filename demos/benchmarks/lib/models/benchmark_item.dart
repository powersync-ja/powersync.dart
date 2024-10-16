import 'package:powersync/sqlite3_common.dart' as sqlite;

import '../powersync.dart';

class BenchmarkItem {
  /// Item id (UUID).
  final String id;

  final String description;

  final DateTime clientCreatedAt;

  final DateTime? serverCreatedAt;

  BenchmarkItem(
      {required this.id,
      required this.description,
      required this.clientCreatedAt,
      this.serverCreatedAt});

  factory BenchmarkItem.fromRow(sqlite.Row row) {
    return BenchmarkItem(
        id: row['id'],
        description: row['description'] ?? '',
        clientCreatedAt: DateTime.parse(row['client_created_at']),
        serverCreatedAt: DateTime.tryParse(row['client_created_at'] ?? ''));
  }

  static Stream<List<BenchmarkItem>> watchItems() {
    return db
        .watch(
            'SELECT * FROM benchmark_items ORDER BY client_created_at DESC, id')
        .map((results) {
      return results.map(BenchmarkItem.fromRow).toList(growable: false);
    });
  }

  /// Create a new list
  static Future<BenchmarkItem> create(String description) async {
    final results = await db.execute('''
      INSERT INTO
        benchmark_items(id, description, client_created_at)
        VALUES(uuid(), ?, datetime())
      RETURNING *
      ''', [description]);
    return BenchmarkItem.fromRow(results.first);
  }

  /// Delete this item.
  Future<void> delete() async {
    await db.execute('DELETE FROM benchmark_items WHERE id = ?', [id]);
  }

  /// Find list item.
  static Future<BenchmarkItem> find(id) async {
    final results =
        await db.get('SELECT * FROM benchmark_items WHERE id = ?', [id]);
    return BenchmarkItem.fromRow(results);
  }
}
