import 'dart:async';
import 'package:meta/meta.dart';
import 'package:fetch_client/fetch_client.dart';
import 'package:logging/logging.dart';
import 'package:powersync/src/abort_controller.dart';
import 'package:powersync/src/bucket_storage.dart';
import 'package:powersync/src/connector.dart';
import 'package:powersync/src/database/powersync_database.dart';
import 'package:powersync/src/database/powersync_db_mixin.dart';
import 'package:powersync/src/database_utils.dart';
import 'package:powersync/src/log.dart';
import 'package:powersync/src/open_factory/abstract_powersync_open_factory.dart';
import 'package:powersync/src/open_factory/web/web_open_factory.dart';
import 'package:powersync/src/schema.dart';
import 'package:powersync/src/streaming_sync.dart';
import 'package:sqlite_async/sqlite_async.dart';
import 'package:powersync/src/schema_helpers.dart' as schema_helpers;

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

  late final DefaultSqliteOpenFactory openFactory;

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
      Logger? logger,
      @Deprecated("Use [PowerSyncDatabase.withFactory] instead.")
      // ignore: deprecated_member_use_from_same_package
      SqliteConnectionSetup? sqliteSetup}) {
    // ignore: deprecated_member_use_from_same_package
    DefaultSqliteOpenFactory factory = PowerSyncOpenFactory(path: path);
    return PowerSyncDatabaseImpl.withFactory(factory,
        maxReaders: maxReaders, logger: logger, schema: schema);
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
      Logger? logger}) {
    final db = SqliteDatabase.withFactory(openFactory, maxReaders: 1);
    return PowerSyncDatabaseImpl.withDatabase(
        schema: schema, logger: logger, database: db);
  }

  /// Open a PowerSyncDatabase on an existing [SqliteDatabase].
  ///
  /// Migrations are run on the database when this constructor is called.
  ///
  /// [logger] defaults to [autoLogger], which logs to the console in debug builds.
  PowerSyncDatabaseImpl.withDatabase(
      {required this.schema, required this.database, Logger? logger}) {
    if (logger != null) {
      this.logger = logger;
    } else {
      this.logger = autoLogger;
    }
    isInitialized = baseInit();
  }

  @override

  /// Connect to the PowerSync service, and keep the databases in sync.
  ///
  /// The connection is automatically re-opened if it fails for any reason.
  ///
  /// Status changes are reported on [statusStream].
  connect({required PowerSyncBackendConnector connector}) async {
    await initialize();

    // Disconnect if connected
    await disconnect();
    disconnecter = AbortController();

    await isInitialized;

    // TODO multitab support
    final storage = BucketStorage(database);

    final sync = StreamingSyncImplementation(
        adapter: storage,
        credentialsCallback: connector.getCredentialsCached,
        invalidCredentialsCallback: connector.fetchCredentials,
        uploadCrud: () => connector.uploadData(this),
        updateStream: updates,
        retryDelay: Duration(seconds: 3),
        // HTTP streaming is not supported on web with the standard http package
        // https://github.com/dart-lang/http/issues/595
        client: FetchClient(mode: RequestMode.cors, streamRequests: true));
    sync.statusStream.listen((event) {
      setStatus(event);
    });
    sync.streamingSync(disconnecter);
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

  @override

  /// Uses the database writeTransaction instead of the locally
  /// scoped writeLock. This is to allow the Database transaction
  /// tracking to be correctly configured.
  Future<T> writeTransaction<T>(
      Future<T> Function(SqliteWriteContext tx) callback,
      {Duration? lockTimeout,
      String? debugContext}) async {
    await isInitialized;
    return database.writeTransaction(
        (context) => internalTrackedWrite(context, callback),
        lockTimeout: lockTimeout);
  }

  @override
  Future<void> updateSchema(Schema schema) {
    if (disconnecter != null) {
      throw AssertionError('Cannot update schema while connected');
    }
    this.schema = schema;
    return database.writeLock((tx) => schema_helpers.updateSchema(tx, schema));
  }
}
