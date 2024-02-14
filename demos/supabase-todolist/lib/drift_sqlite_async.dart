import 'dart:async';

import 'package:drift/backends.dart';
import 'package:drift/drift.dart';
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
    // Could be "INSERT INTO ... RETURNING *", so we need to use execute() instead of getAll()
    final result = await db.execute(statement, args);
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

/// A query executor that uses sqflite internally.
class SqliteAsyncQueryExecutor extends DelegatedDatabase {
  /// A query executor that will store the database in the file declared by
  /// [path]. If [logStatements] is true, statements sent to the database will
  /// be [print]ed, which can be handy for debugging. The [singleInstance]
  /// parameter sets the corresponding parameter on [s.openDatabase].
  /// The [creator] will be called when the database file doesn't exist. It can
  /// be used to, for instance, populate default data from an asset. Note that
  /// migrations might behave differently when populating the database this way.
  /// For instance, a database created by an [creator] will not receive the
  /// [MigrationStrategy.onCreate] callback because it hasn't been created by
  /// drift.
  SqliteAsyncQueryExecutor(s.SqliteConnection db)
      : super(
          _SqliteAsyncDelegate(db),
        );

  /// The underlying SqliteDatabase used by drift to send queries.
  s.SqliteConnection? get db {
    final sqfliteDelegate = delegate as _SqliteAsyncDelegate;
    return sqfliteDelegate.isOpen ? sqfliteDelegate.db : null;
  }

  @override
  // We're not really required to be sequential since sqflite has an internal
  // lock to bring statements into a sequential order.
  // Setting isSequential here helps with cancellations in stream queries
  // though.
  bool get isSequential => true;
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
