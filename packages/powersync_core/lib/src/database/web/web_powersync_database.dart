import 'dart:async';
import 'dart:convert';
import 'package:meta/meta.dart';
import 'package:http/browser_client.dart';
import 'package:logging/logging.dart';
import 'package:powersync_core/src/abort_controller.dart';
import 'package:powersync_core/src/sync/bucket_storage.dart';
import 'package:powersync_core/src/connector.dart';
import 'package:powersync_core/src/database/powersync_database.dart';
import 'package:powersync_core/src/database/powersync_db_mixin.dart';
import 'package:powersync_core/src/log.dart';
import 'package:powersync_core/src/open_factory/abstract_powersync_open_factory.dart';
import 'package:powersync_core/src/open_factory/web/web_open_factory.dart';
import 'package:powersync_core/src/schema.dart';
import 'package:powersync_core/src/sync/internal_connector.dart';
import 'package:powersync_core/src/sync/streaming_sync.dart';
import 'package:sqlite_async/sqlite_async.dart';

import '../../sync/options.dart';
import '../../web/sync_controller.dart';

/// A PowerSync managed database.
///
/// Web implementation for [PowerSyncDatabase]
///
/// Use one instance per database file.
///
/// Use [PowerSyncDatabase.connect] to connect to the PowerSync service,
/// to keep the local database in sync with the remote database.
///
/// All changes to local tables are automatically recorded, whether connected
/// or not. Once connected, the changes are uploaded.
class PowerSyncDatabaseImpl
    with SqliteQueries, PowerSyncDatabaseMixin
    implements PowerSyncDatabase {
  @override
  Schema schema;

  @override
  SqliteDatabase database;

  @override
  bool manualSchemaManagement;

  @override
  @protected
  late Future<void> isInitialized;

  @override

  /// The Logger used by this [PowerSyncDatabase].
  ///
  /// The default is [autoLogger], which logs to the console in debug builds.
  /// Use [debugLogger] to always log to the console.
  /// Use [attachedLogger] to propagate logs to [Logger.root] for custom logging.
  late final Logger logger;

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
  factory PowerSyncDatabaseImpl(
      {required Schema schema,
      required String path,
      int maxReaders = SqliteDatabase.defaultMaxReaders,
      bool manualSchemaManagement = false,
      Logger? logger,
      @Deprecated("Use [PowerSyncDatabase.withFactory] instead.")
      // ignore: deprecated_member_use_from_same_package
      SqliteConnectionSetup? sqliteSetup}) {
    // ignore: deprecated_member_use_from_same_package
    DefaultSqliteOpenFactory factory = PowerSyncOpenFactory(path: path);
    return PowerSyncDatabaseImpl.withFactory(
      factory,
      maxReaders: maxReaders,
      logger: logger,
      schema: schema,
      manualSchemaManagement: manualSchemaManagement,
    );
  }

  /// Open a [PowerSyncDatabase] with a [PowerSyncOpenFactory].
  ///
  /// The factory determines which database file is opened, as well as any
  /// additional logic to run inside the database isolate before or after opening.
  ///
  /// Subclass [PowerSyncOpenFactory] to add custom logic to this process.
  ///
  /// [logger] defaults to [autoLogger], which logs to the console in debug builds.
  factory PowerSyncDatabaseImpl.withFactory(
      DefaultSqliteOpenFactory openFactory,
      {required Schema schema,
      int maxReaders = SqliteDatabase.defaultMaxReaders,
      bool manualSchemaManagement = false,
      Logger? logger}) {
    final db = SqliteDatabase.withFactory(openFactory, maxReaders: 1);
    return PowerSyncDatabaseImpl.withDatabase(
      schema: schema,
      manualSchemaManagement: manualSchemaManagement,
      logger: logger,
      database: db,
    );
  }

  /// Open a PowerSyncDatabase on an existing [SqliteDatabase].
  ///
  /// Migrations are run on the database when this constructor is called.
  ///
  /// [logger] defaults to [autoLogger], which logs to the console in debug builds.
  PowerSyncDatabaseImpl.withDatabase({
    required this.schema,
    required this.database,
    this.manualSchemaManagement = false,
    Logger? logger,
  }) {
    if (logger != null) {
      this.logger = logger;
    } else {
      this.logger = autoLogger;
    }
    isInitialized = baseInit();
  }

  @override
  @internal
  Future<void> connectInternal({
    required PowerSyncBackendConnector connector,
    required AbortController abort,
    required Zone asyncWorkZone,
    required ResolvedSyncOptions options,
  }) async {
    final storage = BucketStorage(database);
    StreamingSync sync;
    // Try using a shared worker for the synchronization implementation to avoid
    // duplicating work across tabs.
    try {
      sync = await SyncWorkerHandle.start(
        database: this,
        connector: connector,
        options: options.source,
        workerUri: Uri.base.resolve('/powersync_sync.worker.js'),
      );
    } catch (e) {
      logger.warning(
        'Could not use shared worker for synchronization, falling back to locks.',
        e,
      );
      final crudStream =
          database.onChange(['ps_crud'], throttle: options.crudThrottleTime);

      sync = StreamingSyncImplementation(
        adapter: storage,
        schemaJson: jsonEncode(schema),
        connector: InternalConnector.wrap(connector, this),
        crudUpdateTriggerStream: crudStream,
        options: options,
        client: BrowserClient(),
        // Only allows 1 sync implementation to run at a time per database
        // This should be global (across tabs) when using Navigator locks.
        identifier: database.openFactory.path,
      );
    }

    sync.statusStream.listen((event) {
      setStatus(event);
    });
    sync.streamingSync();

    abort.onAbort.then((_) async {
      await sync.abort();
      abort.completeAbort();
    }).ignore();
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

  @override
  Future<T> readTransaction<T>(
      Future<T> Function(SqliteReadContext tx) callback,
      {Duration? lockTimeout,
      String? debugContext}) async {
    await isInitialized;
    return database.readTransaction(callback, lockTimeout: lockTimeout);
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

  /// Uses the database writeTransaction instead of the locally
  /// scoped writeLock. This is to allow the Database transaction
  /// tracking to be correctly configured.
  @override
  Future<T> writeTransaction<T>(
      Future<T> Function(SqliteWriteContext tx) callback,
      {Duration? lockTimeout,
      String? debugContext}) async {
    await isInitialized;
    return database.writeTransaction(callback, lockTimeout: lockTimeout);
  }
}
