import 'package:powersync/powersync.dart';

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
