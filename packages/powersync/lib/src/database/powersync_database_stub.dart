import 'dart:async';

import 'package:logging/src/logger.dart';
import 'package:powersync/sqlite_async.dart';
import 'package:powersync/src/open_factory/abstract_powersync_open_factory.dart';
import 'abstract_powersync_database.dart';

import '../connector.dart';
import '../schema.dart';

class PowerSyncDatabase extends AbstractPowerSyncDatabase {
  @override
  Future<void> close() {
    throw UnimplementedError();
  }

  @override
  bool get closed => throw UnimplementedError();

  @override
  Schema get schema => throw UnimplementedError();

  @override
  SqliteDatabase get database => throw UnimplementedError();

  @override
  Future<void> get isInitialized => throw UnimplementedError();

  /// Open a [PowerSyncDatabase].
  ///
  /// Only a single [PowerSyncDatabase] per [path] should be opened at a time.
  ///
  /// The specified [schema] is used for the database.
  ///
  /// A connection pool is used by default, allowing multiple concurrent read
  /// transactions, and a single concurrent write transaction. Write transactions
  /// do not block read transactions, and read transactions will see the state
  /// from the last committed write transaction.
  ///
  /// A maximum of [maxReaders] concurrent read transactions are allowed.
  ///
  /// [logger] defaults to [autoLogger], which logs to the console in debug builds.
  PowerSyncDatabase(
      {required Schema schema,
      required String path,
      int maxReaders = AbstractSqliteDatabase.defaultMaxReaders,
      Logger? logger,
      @Deprecated("Use [PowerSyncDatabase.withFactory] instead")
      // ignore: deprecated_member_use_from_same_package
      SqliteConnectionSetup? sqliteSetup});

  /// Open a [PowerSyncDatabase] with a [PowerSyncOpenFactory].
  ///
  /// The factory determines which database file is opened, as well as any
  /// additional logic to run inside the database isolate before or after opening.
  ///
  /// Subclass [PowerSyncOpenFactory] to add custom logic to this process.
  ///
  /// [logger] defaults to [autoLogger], which logs to the console in debug builds.s
  factory PowerSyncDatabase.withFactory(
    DefaultSqliteOpenFactory openFactory, {
    required Schema schema,
    int maxReaders = AbstractSqliteDatabase.defaultMaxReaders,
    Logger? logger,
  }) {
    throw UnimplementedError();
  }

  /// Open a PowerSyncDatabase on an existing [SqliteDatabase].
  ///
  /// Migrations are run on the database when this constructor is called.
  ///
  /// [logger] defaults to [autoLogger], which logs to the console in debug builds.s
  PowerSyncDatabase.withDatabase(
      {required Schema schema,
      required SqliteDatabase database,
      Logger? loggers}) {
    throw UnimplementedError();
  }

  @override
  connect({required PowerSyncBackendConnector connector}) {
    throw UnimplementedError();
  }

  @override
  Future<T> readLock<T>(Future<T> Function(SqliteReadContext tx) callback,
      {String? debugContext, Duration? lockTimeout}) {
    throw UnimplementedError();
  }

  @override
  Future<T> writeLock<T>(Future<T> Function(SqliteWriteContext tx) callback,
      {String? debugContext, Duration? lockTimeout}) {
    throw UnimplementedError();
  }

  @override
  Future<bool> getAutoCommit() {
    throw UnimplementedError();
  }

  @override
  Future<void> updateSchema(Schema schema) {
    throw UnimplementedError();
  }

  @override
  // TODO: implement logger
  Logger get logger => throw UnimplementedError();
}
