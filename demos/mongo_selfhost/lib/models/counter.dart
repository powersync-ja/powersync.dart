import 'package:sqlite_async/sqlite3_common.dart' as sqlite;

import '../powersync/powersync.dart';

class Counter {
  final String userId;
  final int count;

  Counter({required this.userId, required this.count});

  factory Counter.fromRow(sqlite.Row row) {
    return Counter(userId: row['user_id'], count: row['count']);
  }

  static Stream<Counter?> watchCurrentUserCounter(String userId) {
    return db
        .watch(
          'SELECT * FROM counter WHERE user_id = ?',
          parameters: [userId],
        )
        .map((results) {
          if (results.isEmpty) return null;
          return Counter.fromRow(results.first);
        });
  }

  static Stream<List<Counter>> watchAllCounters() {
    return db.watch('SELECT * FROM counter ORDER BY user_id').map((results) {
      return results.map(Counter.fromRow).toList(growable: false);
    });
  }

  static Future<void> increment(String userId) async {
    await db.execute('UPDATE counter SET count = count + 1 WHERE user_id = ?', [
      userId,
    ]);
  }

  static Future<void> create(String userId) async {
    await db.execute(
      'INSERT INTO counter(id, user_id, count) VALUES(uuid(), ?, 0)',
      [userId],
    );
  }

  static Future<void> incrementCurrentUser(String userId) async {
    await increment(userId);
  }
}