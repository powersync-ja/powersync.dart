import 'dart:async';

import 'package:powersync/sqlite_async.dart';
import 'abstract_powersync_database.dart';

import '../connector.dart';
import '../schema.dart';

class PowerSyncDatabase extends AbstractPowerSyncDatabase {
  PowerSyncDatabase({required Schema schema, required String path});

  @override
  Future<void> close() {
    throw UnimplementedError();
  }

  @override
  bool get closed => throw UnimplementedError();

  @override
  connect({required PowerSyncBackendConnector connector}) {
    throw UnimplementedError();
  }

  @override
  Schema get schema => throw UnimplementedError();

  @override
  SqliteDatabase get database => throw UnimplementedError();

  @override
  Future<void> get isInitialized => throw UnimplementedError();

  /// Open a [PowerSyncDatabase] with a [PowerSyncOpenFactory].
  ///
  /// The factory determines which database file is opened, as well as any
  /// additional logic to run inside the database isolate before or after opening.
  ///
  /// Subclass [PowerSyncOpenFactory] to add custom logic to this process.
  factory PowerSyncDatabase.withFactory(DefaultSqliteOpenFactory openFactory,
      {required Schema schema,
      int maxReaders = AbstractSqliteDatabase.defaultMaxReaders}) {
    throw UnimplementedError();
  }

  /// Open a PowerSyncDatabase on an existing [SqliteDatabase].
  ///
  /// Migrations are run on the database when this constructor is called.
  PowerSyncDatabase.withDatabase(
      {required Schema schema, required SqliteDatabase database}) {
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
}
