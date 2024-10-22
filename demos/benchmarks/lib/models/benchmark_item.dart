import 'package:powersync/sqlite3_common.dart' as sqlite;

import '../powersync.dart';

class BenchmarkItem {
  /// Item id (UUID).
  final String id;

  final String description;

  final DateTime clientCreatedAt;
  final DateTime? clientReceivedAt;

  final DateTime? serverCreatedAt;

  BenchmarkItem(
      {required this.id,
      required this.description,
      required this.clientCreatedAt,
      this.clientReceivedAt,
      this.serverCreatedAt});

  factory BenchmarkItem.fromRow(sqlite.Row row) {
    return BenchmarkItem(
        id: row['id'],
        description: row['description'] ?? '',
        clientCreatedAt: DateTime.parse(row['client_created_at']),
        clientReceivedAt: DateTime.tryParse(row['client_received_at'] ?? ''),
        serverCreatedAt: DateTime.tryParse(row['server_created_at'] ?? ''));
  }

  static Stream<List<BenchmarkItem>> watchItems() {
    return db
        .watch(
            'SELECT * FROM benchmark_items ORDER BY client_created_at DESC, id')
        .map((results) {
      return results.map(BenchmarkItem.fromRow).toList(growable: false);
    });
  }

  static updateItemBenchmarks() async {
    await for (var _ in db.onChange(['benchmark_items'],
        throttle: const Duration(milliseconds: 1))) {
      await db.execute(
          '''UPDATE benchmark_items SET client_received_at = datetime('now', 'subsecond') || 'Z' WHERE client_received_at IS NULL AND server_created_at IS NOT NULL''');
    }
  }

  /// Create a new list
  static Future<BenchmarkItem> create(String description) async {
    final results = await db.execute('''
      INSERT INTO
        benchmark_items(id, description, client_created_at)
        VALUES(uuid(), ?, datetime('now', 'subsecond') || 'Z')
      RETURNING *
      ''', [description]);
    return BenchmarkItem.fromRow(results.first);
  }

  /// Find list item.
  static Future<BenchmarkItem> find(id) async {
    final results =
        await db.get('SELECT * FROM benchmark_items WHERE id = ?', [id]);
    return BenchmarkItem.fromRow(results);
  }

  static Future<void> deleteAll() async {
    await db.execute(
      'DELETE FROM benchmark_items',
    );
  }

  /// Delete this item.
  Future<void> delete() async {
    await db.execute('DELETE FROM benchmark_items WHERE id = ?', [id]);
  }

  Duration? get latency {
    if (clientReceivedAt == null) {
      return null;
    } else {
      return clientReceivedAt!.difference(clientCreatedAt);
    }
  }

  Duration? get uploadLatency {
    if (serverCreatedAt == null) {
      return null;
    } else {
      return serverCreatedAt!.difference(clientCreatedAt);
    }
  }
}
