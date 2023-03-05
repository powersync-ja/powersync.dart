import 'dart:async';

import 'package:powersync/powersync.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;

Future<T> internalReadTransaction<T>(SqliteReadTransactionContext ctx,
    Future<T> Function(SqliteReadTransactionContext tx) callback) async {
  try {
    await ctx.getAll('BEGIN');
    final result = await callback(ctx);
    await ctx.getAll('END TRANSACTION');
    return result;
  } catch (e) {
    try {
      await ctx.getAll('ROLLBACK');
    } catch (e) {
      // In rare cases, a ROLLBACK may fail.
      // Safe to ignore.
    }
    rethrow;
  }
}

Future<T> internalWriteTransaction<T>(SqliteWriteTransactionContext ctx,
    Future<T> Function(SqliteWriteTransactionContext tx) callback) async {
  try {
    await ctx.execute('BEGIN IMMEDIATE');
    final result = await callback(ctx);
    await ctx.execute('COMMIT');
    return result;
  } catch (e) {
    try {
      await ctx.execute('ROLLBACK');
    } catch (e) {
      // In rare cases, a ROLLBACK may fail.
      // Safe to ignore.
    }
    rethrow;
  }
}

Future<T> asyncDirectTransaction<T>(sqlite.Database db,
    FutureOr<T> Function(sqlite.Database db) callback) async {
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
