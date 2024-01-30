import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:powersync/src/open_factory/abstract_powersync_open_factory.dart';
import 'package:powersync/src/open_factory/web/web_open_factory.dart';
import 'package:powersync/src/streaming_sync.dart';
import 'package:sqlite_async/sqlite_async.dart';

import '../../bucket_storage.dart';
import '../../schema_helpers.dart' as schema_helpers;
import '../abstract_powersync_database.dart';

import '../../abort_controller.dart';
import '../../connector.dart';
import '../../schema.dart';

/// A PowerSync managed database.
///
/// Use one instance per database file.
///
/// Use [PowerSyncDatabase.connect] to connect to the PowerSync service,
/// to keep the local database in sync with the remote database.
///
/// All changes to local tables are automatically recorded, whether connected
/// or not. Once connected, the changes are uploaded.
class PowerSyncDatabase extends AbstractPowerSyncDatabase {
  @override
  Schema schema;

  @override
  SqliteDatabase database;

  late final DefaultSqliteOpenFactory openFactory;

  @override
  @protected
  late Future<void> isInitialized;

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
  factory PowerSyncDatabase(
      {required Schema schema,
      required String path,
      @Deprecated("Use [PowerSyncDatabase.withFactory] instead")
      // ignore: deprecated_member_use_from_same_package
      SqliteConnectionSetup? sqliteSetup}) {
    // ignore: deprecated_member_use_from_same_package
    DefaultSqliteOpenFactory factory = PowerSyncOpenFactory(path: path);
    return PowerSyncDatabase.withFactory(factory, schema: schema);
  }

  /// Open a [PowerSyncDatabase] with a [PowerSyncOpenFactory].
  ///
  /// The factory determines which database file is opened, as well as any
  /// additional logic to run inside the database isolate before or after opening.
  ///
  /// Subclass [PowerSyncOpenFactory] to add custom logic to this process.
  factory PowerSyncDatabase.withFactory(DefaultSqliteOpenFactory openFactory,
      {required Schema schema,
      int maxReaders = AbstractSqliteDatabase.defaultMaxReaders}) {
    final db = SqliteDatabase.withFactory(openFactory, maxReaders: 1);
    return PowerSyncDatabase.withDatabase(schema: schema, database: db);
  }

  /// Open a PowerSyncDatabase on an existing [SqliteDatabase].
  ///
  /// Migrations are run on the database when this constructor is called.
  PowerSyncDatabase.withDatabase(
      {required this.schema, required this.database}) {
    isInitialized = _init();
  }

  Future<void> _init() async {
    await super.baseInit();
    // Update schema
    await updateSchema(schema);
  }

  @override

  /// Connect to the PowerSync service, and keep the databases in sync.
  ///
  /// The connection is automatically re-opened if it fails for any reason.
  ///
  /// Status changes are reported on [statusStream].
  connect({required PowerSyncBackendConnector connector}) async {
    // Disconnect if connected
    await disconnect();
    final disconnector = AbortController();
    disconnecter = disconnector;

    await isInitialized;

    // TODO multitab support
    final storage = BucketStorage(database);
    final sync = StreamingSyncImplementation(
        adapter: storage,
        credentialsCallback: connector.getCredentialsCached,
        invalidCredentialsCallback: connector.fetchCredentials,
        uploadCrud: () => connector.uploadData(this),
        updateStream: updates,
        retryDelay: Duration(seconds: 3));
    sync.streamingSync();
  }

  /// Takes a read lock, without starting a transaction.
  ///
  /// In most cases, [readTransaction] should be used instead.
  @override
  Future<T> readLock<T>(Future<T> Function(SqliteReadContext tx) callback,
      {String? debugContext, Duration? lockTimeout}) async {
    await isInitialized;
    return database.readLock(callback,
        debugContext: debugContext, lockTimeout: lockTimeout);
  }

  /// Takes a global lock, without starting a transaction.
  ///
  /// In most cases, [writeTransaction] should be used instead.
  @override
  Future<T> writeLock<T>(Future<T> Function(SqliteWriteContext tx) callback,
      {String? debugContext, Duration? lockTimeout}) async {
    await isInitialized;
    return database.writeLock(callback,
        debugContext: debugContext, lockTimeout: lockTimeout);
  }

  @override
  Future<void> updateSchema(Schema schema) {
    if (disconnecter != null) {
      throw AssertionError('Cannot update schema while connected');
    }
    this.schema = schema;
    return database
        .writeLock((tx) async => schema_helpers.updateSchema(tx, schema));
  }
}
