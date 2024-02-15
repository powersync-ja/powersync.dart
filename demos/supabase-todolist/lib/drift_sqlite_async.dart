import 'dart:async';

import 'package:drift/backends.dart';
import 'package:powersync/sqlite_async.dart';
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
      const NoTransactionDelegate();

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

  @override
  TransactionExecutor beginTransaction() {
    return _SqliteAsyncTransactionExecutor(db);
  }
}

abstract class _QueryDelegate {
  SqliteWriteContext get ctx;
}

mixin _QueryMixin implements QueryExecutor, _QueryDelegate {
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
  Future<void> runCustom(String statement, [List<Object?>? args]) {
    return ctx.execute(statement, args ?? const []);
  }

  @override
  Future<int> runInsert(String statement, List<Object?> args) async {
    await ctx.execute(statement, args);
    final row = await ctx.get('SELECT last_insert_rowid() as row_id');
    return row['row_id'];
  }

  @override
  Future<List<Map<String, Object?>>> runSelect(
      String statement, List<Object?> args) async {
    final result = await ctx.execute(statement, args);
    return QueryResult(result.columnNames, result.rows).asMap.toList();
  }

  @override
  Future<int> runUpdate(String statement, List<Object?> args) async {
    await ctx.execute(statement, args);
    final row = await ctx.get('SELECT changes() as changes');
    return row['changes'];
  }

  @override
  Future<int> runDelete(String statement, List<Object?> args) {
    return runUpdate(statement, args);
  }
}

/// Based on _WrappingTransactionExecutor, which is private.
/// Extended to support nested transactions.
class _SqliteAsyncTransactionExecutor extends TransactionExecutor
    with _QueryMixin {
  final s.SqliteConnection _db;
  static final _artificialRollback =
      Exception('artificial exception to rollback the transaction');
  final Zone _createdIn = Zone.current;
  final Completer<void> _completerForCallback = Completer();
  Completer<void>? _opened, _finished;

  /// Whether this executor has explicitly been closed.
  bool _closed = false;

  @override
  late SqliteWriteContext ctx;

  _SqliteAsyncTransactionExecutor(this._db);

  void _checkCanOpen() {
    if (_closed) {
      throw StateError(
          "A tranaction was used after being closed. Please check that you're "
          'awaiting all database operations inside a `transaction` block.');
    }
  }

  @override
  Future<bool> ensureOpen(QueryExecutorUser user) {
    _checkCanOpen();
    var opened = _opened;

    if (opened == null) {
      _opened = opened = Completer();
      _createdIn.run(() async {
        final result = _db.writeTransaction((innerCtx) async {
          opened!.complete();
          ctx = innerCtx;
          await _completerForCallback.future;
        });

        _finished = Completer()
          ..complete(
            // ignore: void_checks
            result
                // Ignore the exception caused by [rollback] which may be
                // rethrown by startTransaction
                .onError<Exception>((error, stackTrace) => null,
                    test: (e) => e == _artificialRollback)
                // Consider this transaction closed after the call completes
                // This may happen without send/rollback being called in
                // case there's an exception when opening the transaction.
                .whenComplete(() => _closed = true),
          );
      });
    }

    // The opened completer is never completed if `startTransaction` throws
    // before our callback is invoked (probably becaue `BEGIN` threw an
    // exception). In that case, _finished will complete with that error though.
    return Future.any([opened.future, if (_finished != null) _finished!.future])
        .then((value) => true);
  }

  @override
  Future<void> send() async {
    // don't do anything if the transaction completes before it was opened
    if (_opened == null || _closed) return;

    _completerForCallback.complete();
    _closed = true;
    await _finished?.future;
  }

  @override
  Future<void> rollback() async {
    // Note: This may be called after send() if send() throws (that is, the
    // transaction can't be completed). But if completing fails, we assume that
    // the transaction will implicitly be rolled back the underlying connection
    // (it's not like we could explicitly roll it back, we only have one
    // callback to implement).
    if (_opened == null || _closed) return;

    _completerForCallback.completeError(_artificialRollback);
    _closed = true;
    await _finished?.future;
  }

  @override
  TransactionExecutor beginTransaction() {
    return _SqliteAsyncNestedTransactionExecutor(ctx, 1);
  }

  @override
  SqlDialect get dialect => SqlDialect.sqlite;

  @override
  bool get supportsNestedTransactions => true;
}

class _SqliteAsyncNestedTransactionExecutor extends TransactionExecutor
    with _QueryMixin {
  @override
  final SqliteWriteContext ctx;

  int depth;

  _SqliteAsyncNestedTransactionExecutor(this.ctx, this.depth);

  @override
  Future<bool> ensureOpen(QueryExecutorUser user) async {
    await ctx.execute('SAVEPOINT tx$depth');
    return true;
  }

  @override
  Future<void> send() async {
    await ctx.execute('RELEASE SAVEPOINT tx$depth');
  }

  @override
  Future<void> rollback() async {
    await ctx.execute('ROLLBACK TO SAVEPOINT tx$depth');
  }

  @override
  TransactionExecutor beginTransaction() {
    return _SqliteAsyncNestedTransactionExecutor(ctx, depth + 1);
  }

  @override
  SqlDialect get dialect => SqlDialect.sqlite;

  @override
  bool get supportsNestedTransactions => true;
}
