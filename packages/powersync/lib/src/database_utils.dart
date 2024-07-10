import 'dart:async';

import 'package:sqlite_async/sqlite3.dart' as sqlite;
import 'package:sqlite_async/sqlite3_common.dart';

Future<T> asyncDirectTransaction<T>(
    CommonDatabase db, FutureOr<T> Function(CommonDatabase db) callback) async {
  for (var i = 50; i >= 0; i--) {
    try {
      db.execute('BEGIN IMMEDIATE');
      late T result;
      try {
        result = await callback(db);
        db.execute('COMMIT');
      } catch (e) {
        try {
          db.execute('ROLLBACK');
        } catch (e2) {
          // Safe to ignore
        }
        rethrow;
      }

      return result;
    } catch (e) {
      if (e is sqlite.SqliteException) {
        if (e.resultCode == 5 && i != 0) {
          // SQLITE_BUSY
          await Future.delayed(const Duration(milliseconds: 50));
          continue;
        }
      }
      rethrow;
    }
  }
  throw AssertionError('Should not reach this');
}
