import 'dart:async';

import 'package:drift/backends.dart';
import 'package:sqlite_async/sqlite3.dart';
import 'package:sqlite_async/sqlite_async.dart' as s;

class _SqliteAsyncDelegate extends DatabaseDelegate {
  final s.SqliteConnection db;

  _SqliteAsyncDelegate(this.db);

  @override
  late final DbVersionDelegate versionDelegate =
      _SqliteAsyncVersionDelegate(db);

  @override
  late final TransactionDelegate transactionDelegate =
      _SqliteAsyncTransactionDelegate(db);

  @override
  bool get isOpen => !db.closed;

  // Ends with " RETURNING *", or starts with insert/update/delete.
  // Drift-generated queries will always have the RETURNING *.
  // The INSERT/UPDATE/DELETE check is for custom queries, and is not exhaustive.
  final _returningCheck = RegExp(
      r'( RETURNING \*;?$)|(^(INSERT|UPDATE|DELETE))',
      caseSensitive: false);

  @override
  Future<void> open(QueryExecutorUser user) async {
    // Workaround - this ensures the db is open
    await db.get('SELECT 1');
  }

  @override
  Future<void> close() {
    return db.close();
  }

  @override
  Future<void> runBatched(BatchedStatements statements) async {
    return db.writeLock((tx) async {
      // sqlite_async's batch functionality doesn't have enough flexibility to support
      // this with prepared statements yet.
      for (final arg in statements.arguments) {
        await tx.execute(
            statements.statements[arg.statementIndex], arg.arguments);
      }
    });
  }

  @override
  Future<void> runCustom(String statement, List<Object?> args) {
    return db.execute(statement, args);
  }

  @override
  Future<int> runInsert(String statement, List<Object?> args) async {
    return db.writeLock((tx) async {
      await tx.execute(statement, args);
      final row = await tx.get('SELECT last_insert_rowid() as row_id');
      return row['row_id'];
    });
  }

  @override
  Future<QueryResult> runSelect(String statement, List<Object?> args) async {
    ResultSet result;
    if (_returningCheck.hasMatch(statement)) {
      // Could be "INSERT INTO ... RETURNING *" (or update or delete),
      // so we need to use execute() instead of getAll().
      // This takes write lock, so we want to avoid it for plain select statements.
      // This is not an exhaustive check, but should cover all Drift-generated queries using
      // `runSelect()`.
      result = await db.execute(statement, args);
    } else {
      // Plain SELECT statement - use getAll() to avoid using a write lock.
      result = await db.getAll(statement, args);
    }
    return QueryResult(result.columnNames, result.rows);
  }

  @override
  Future<int> runUpdate(String statement, List<Object?> args) {
    return db.writeLock((tx) async {
      await tx.execute(statement, args);
      final row = await tx.get('SELECT changes() as changes');
      return row['changes'];
    });
  }
}

class _SqliteAsyncQueryDelegate extends QueryDelegate {
  final s.SqliteWriteContext ctx;

  _SqliteAsyncQueryDelegate(this.ctx);

  @override
  Future<void> runBatched(BatchedStatements statements) async {
    // sqlite_async's batch functionality doesn't have enough flexibility to support
    // this with prepared statements yet.
    for (final arg in statements.arguments) {
      await ctx.execute(
          statements.statements[arg.statementIndex], arg.arguments);
    }
  }

  @override
  Future<void> runCustom(String statement, List<Object?> args) {
    return ctx.execute(statement, args);
  }

  @override
  Future<int> runInsert(String statement, List<Object?> args) async {
    await ctx.execute(statement, args);
    final row = await ctx.get('SELECT last_insert_rowid() as row_id');
    return row['row_id'];
  }

  @override
  Future<QueryResult> runSelect(String statement, List<Object?> args) async {
    final result = await ctx.execute(statement, args);
    return QueryResult(result.columnNames, result.rows);
  }

  @override
  Future<int> runUpdate(String statement, List<Object?> args) async {
    await ctx.execute(statement, args);
    final row = await ctx.get('SELECT changes() as changes');
    return row['changes'];
  }
}

class _SqliteAsyncVersionDelegate extends DynamicVersionDelegate {
  final s.SqliteConnection _db;

  _SqliteAsyncVersionDelegate(this._db);

  @override
  Future<int> get schemaVersion async {
    final result = await _db.get('PRAGMA user_version;');
    return result['user_version'];
  }

  @override
  Future<void> setSchemaVersion(int version) async {
    await _db.execute('PRAGMA user_version = $version;');
  }
}

/// A query executor that uses sqlite_async internally.
class SqliteAsyncQueryExecutor extends DelegatedDatabase {
  SqliteAsyncQueryExecutor(s.SqliteConnection db)
      : super(
          _SqliteAsyncDelegate(db),
        );

  /// The underlying SqliteConnection used by drift to send queries.
  s.SqliteConnection get db {
    return (delegate as _SqliteAsyncDelegate).db;
  }

  @override
  bool get isSequential => false;
}

class _SqliteAsyncTransactionDelegate extends SupportedTransactionDelegate {
  final s.SqliteConnection _db;

  _SqliteAsyncTransactionDelegate(this._db);

  @override
  FutureOr<void> startTransaction(Future Function(QueryDelegate p1) run) {
    return _db.writeTransaction((tx) async {
      await run(_SqliteAsyncQueryDelegate(tx));
    });
  }
}
