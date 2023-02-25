import 'package:sqlite3/sqlite3.dart' as sqlite;

/// Abstract class representing calls available in a read-only or read-write context.
abstract class SqliteReadTransactionContext {
  /// Execute a read-only (SELECT) query and return the results.
  Future<sqlite.ResultSet> getAll(String sql,
      [List<Object?> parameters = const []]);

  /// Execute a read-only (SELECT) query and return a single result.
  Future<sqlite.Row> get(String sql, [List<Object?> parameters = const []]);

  /// Execute a read-only (SELECT) query and return a single optional result.
  Future<sqlite.Row?> getOptional(String sql,
      [List<Object?> parameters = const []]);
}

/// Abstract class representing calls available in a read-write context.
abstract class SqliteWriteTransactionContext
    extends SqliteReadTransactionContext {
  /// Execute a write query (INSERT, UPDATE, DELETE) and return the results.
  Future<sqlite.ResultSet> execute(String sql,
      [List<Object?> parameters = const []]);
}

/// Abstract class representing a connection to the SQLite database.
abstract class SqliteConnection extends SqliteWriteTransactionContext {
  /// Open a read-only transaction.
  ///
  /// Statements within the transaction must be done on the provided
  /// [SqliteReadTransactionContext] - attempting statements on the [SqliteConnection]
  /// instance will error.
  Future<T> readTransaction<T>(
      Future<T> Function(SqliteReadTransactionContext tx) callback,
      {Duration? lockTimeout});

  /// Open a read-write transaction.
  ///
  /// This takes a global lock - only one write transaction can execute against
  /// the database at a time.
  ///
  /// Statements within the transaction must be done on the provided
  /// [SqliteWriteTransactionContext] - attempting statements on the [SqliteConnection]
  /// instance will error.
  Future<T> writeTransaction<T>(
      Future<T> Function(SqliteWriteTransactionContext tx) callback,
      {Duration? lockTimeout});

  /// Execute a read query every time the source tables are modified.
  ///
  /// Use [throttle] to specify the minimum interval between queries.
  Stream<sqlite.ResultSet> watch(String sql,
      {List<Object?> parameters = const [],
      Duration throttle = const Duration(milliseconds: 30)});
}
