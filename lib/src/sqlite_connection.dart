import 'package:collection/collection.dart';
import 'package:powersync/src/database_utils.dart';
import 'package:powersync/src/throttle.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;

/// Abstract class representing calls available in a read-only or read-write context.
abstract class SqliteReadContext {
  /// Execute a read-only (SELECT) query and return the results.
  Future<sqlite.ResultSet> getAll(String sql,
      [List<Object?> parameters = const []]);

  /// Execute a read-only (SELECT) query and return a single result.
  Future<sqlite.Row> get(String sql, [List<Object?> parameters = const []]);

  /// Execute a read-only (SELECT) query and return a single optional result.
  Future<sqlite.Row?> getOptional(String sql,
      [List<Object?> parameters = const []]);

  /// Run a function within a database isolate, with direct synchronous access
  /// to the underlying database.
  ///
  /// Using closures must be done with care, since values are sent over to the
  /// database isolate. To be safe, use this from a top-level function, taking
  /// only required arguments.
  ///
  /// The database may only be used within the callback, and only until the
  /// returned future returns. If it is used outside of that, it could cause
  /// unpredictable issues in other transactions.
  ///
  /// Example:
  ///
  /// ```dart
  /// Future<void> largeBatchInsert(SqliteConnection connection, List<List<Object>> rows) {
  ///   await connection.writeTransaction((tx) async {
  ///     await tx.computeWithDatabase((db) async {
  ///       final statement = db.prepare('INSERT INTO data(id, value) VALUES (?, ?)');
  ///       try {
  ///         for (var row in rows) {
  ///           statement.execute(row);
  ///         }
  ///       } finally {
  ///         statement.dispose();
  ///       }
  ///     });
  ///   });
  /// }
  /// ```
  Future<T> computeWithDatabase<T>(
      Future<T> Function(sqlite.Database db) compute);
}

/// Abstract class representing calls available in a read-write context.
abstract class SqliteWriteContext extends SqliteReadContext {
  /// Execute a write query (INSERT, UPDATE, DELETE) and return the results (if any).
  Future<sqlite.ResultSet> execute(String sql,
      [List<Object?> parameters = const []]);

  /// Execute a write query (INSERT, UPDATE, DELETE) multiple times with each
  /// parameter set. This is more faster than executing separately with each
  /// parameter set.
  Future<void> executeBatch(String sql, List<List<Object?>> parameterSets);
}

/// Abstract class representing a connection to the SQLite database.
abstract class SqliteConnection extends SqliteWriteContext {
  /// Open a read-only transaction.
  ///
  /// Statements within the transaction must be done on the provided
  /// [SqliteReadContext] - attempting statements on the [SqliteConnection]
  /// instance will error.
  Future<T> readTransaction<T>(
      Future<T> Function(SqliteReadContext tx) callback,
      {Duration? lockTimeout});

  /// Open a read-write transaction.
  ///
  /// This takes a global lock - only one write transaction can execute against
  /// the database at a time.
  ///
  /// Statements within the transaction must be done on the provided
  /// [SqliteWriteContext] - attempting statements on the [SqliteConnection]
  /// instance will error.
  Future<T> writeTransaction<T>(
      Future<T> Function(SqliteWriteContext tx) callback,
      {Duration? lockTimeout});

  /// Execute a read query every time the source tables are modified.
  ///
  /// Use [throttle] to specify the minimum interval between queries.
  Stream<sqlite.ResultSet> watch(String sql,
      {List<Object?> parameters = const [],
      Duration throttle = const Duration(milliseconds: 30)});

  /// Takes a read lock, without starting a transaction.
  ///
  /// In most cases, [readTransaction] should be used instead.
  Future<T> readLock<T>(Future<T> Function(SqliteReadContext tx) callback,
      {Duration? lockTimeout});

  /// Takes a global lock, without starting a transaction.
  ///
  /// In most cases, [writeTransaction] should be used instead.
  Future<T> writeLock<T>(Future<T> Function(SqliteWriteContext tx) callback,
      {Duration? lockTimeout});
}

/// Represents an update to one or more tables, for the purpose of realtime change
/// notifications.
///
/// The update could be from local or remote changes.
class TableUpdate {
  /// Table name
  final Set<String> tables;

  const TableUpdate(this.tables);

  const TableUpdate.empty() : tables = const {};
  TableUpdate.single(String table) : tables = {table};

  @override
  bool operator ==(Object other) {
    return other is TableUpdate &&
        const SetEquality<String>().equals(other.tables, tables);
  }

  @override
  int get hashCode {
    return Object.hashAllUnordered(tables);
  }

  @override
  String toString() {
    return "TableUpdate<$tables>";
  }

  bool containsAny(Set<String> tableFilter) {
    for (var table in tables) {
      if (tableFilter.contains(table.toLowerCase())) {
        return true;
      }
    }
    return false;
  }
}

mixin SqliteQueries implements SqliteWriteContext, SqliteConnection {
  Stream<TableUpdate>? get updates;

  @override
  Future<sqlite.ResultSet> execute(String sql,
      [List<Object?> parameters = const []]) async {
    return writeLock((ctx) async {
      return ctx.execute(sql, parameters);
    });
  }

  @override
  Future<sqlite.ResultSet> getAll(String sql,
      [List<Object?> parameters = const []]) {
    return readLock((ctx) async {
      return ctx.getAll(sql, parameters);
    });
  }

  @override
  Future<sqlite.Row> get(String sql, [List<Object?> parameters = const []]) {
    return readLock((ctx) async {
      return ctx.get(sql, parameters);
    });
  }

  @override
  Future<sqlite.Row?> getOptional(String sql,
      [List<Object?> parameters = const []]) {
    return readLock((ctx) async {
      return ctx.getOptional(sql, parameters);
    });
  }

  @override
  Stream<sqlite.ResultSet> watch(String sql,
      {List<Object?> parameters = const [],
      Duration throttle = const Duration(milliseconds: 30),
      Iterable<String>? triggerOnTables}) async* {
    assert(updates != null,
        'updates stream must be provided to allow query watching');
    final tables = triggerOnTables ?? await getSourceTables(this, sql);
    final filteredStream = updates!.transform(filterTablesTransformer(tables));
    final throttledStream = throttleTableUpdates(filteredStream, throttle,
        addOne: TableUpdate.empty());

    // FIXME:
    // When the subscription is cancelled, this performs a final query on the next
    // update.
    // The loop only stops once the "yield" is reached.
    // Using asyncMap instead of a generator would solve it, but then the body
    // here can't be async for getSourceTables().
    await for (var _ in throttledStream) {
      yield await getAll(sql, parameters);
    }
  }

  /// Create a Stream of changes to any of the specified tables.
  ///
  /// Example to get the same effect as [watch]:
  ///
  /// ```dart
  /// var subscription = db.onChange({'mytable'}).asyncMap((event) async {
  ///   var data = await db.getAll('SELECT * FROM mytable');
  ///   return data;
  /// }).listen((data) {
  ///   // Do something with the data here
  /// });
  /// ```
  ///
  /// This is preferred over [watch] when multiple queries need to be performed
  /// together when data is changed.
  Stream<TableUpdate> onChange(Iterable<String>? tables,
      {Duration throttle = const Duration(milliseconds: 30),
      bool triggerImmediately = true}) {
    assert(updates != null,
        'updates stream must be provided to allow query watching');
    final filteredStream = tables != null
        ? updates!.transform(filterTablesTransformer(tables))
        : updates!;
    final throttledStream = throttleTableUpdates(filteredStream, throttle,
        addOne: triggerImmediately ? TableUpdate.empty() : null);
    return throttledStream;
  }

  @override
  Future<T> readTransaction<T>(
      Future<T> Function(SqliteReadContext tx) callback,
      {Duration? lockTimeout}) async {
    return readLock((ctx) async {
      return await internalReadTransaction(ctx, callback);
    }, lockTimeout: lockTimeout);
  }

  @override
  Future<T> writeTransaction<T>(
      Future<T> Function(SqliteWriteContext tx) callback,
      {Duration? lockTimeout}) async {
    return writeLock((ctx) async {
      return await internalWriteTransaction(ctx, callback);
    }, lockTimeout: lockTimeout);
  }

  /// See [SqliteReadContext.computeWithDatabase].
  ///
  /// When called here directly on the connection, the call is wrapped in a
  /// write transaction.
  @override
  Future<T> computeWithDatabase<T>(
      Future<T> Function(sqlite.Database db) compute) {
    return writeTransaction((tx) async {
      return tx.computeWithDatabase(compute);
    });
  }

  /// Execute a write query (INSERT, UPDATE, DELETE) multiple times with each
  /// parameter set. This is more faster than executing separately with each
  /// parameter set.
  ///
  /// When called here directly on the connection, the batch is wrapped in a
  /// write transaction.
  @override
  Future<void> executeBatch(String sql, List<List<Object?>> parameterSets) {
    return writeTransaction((tx) async {
      return tx.executeBatch(sql, parameterSets);
    });
  }
}
