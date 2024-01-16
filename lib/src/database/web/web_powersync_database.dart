import 'dart:async';

import 'package:powersync/src/open_factory/open_factory_interface.dart';
import 'package:powersync/src/open_factory/web/web_open_factory.dart';
import 'package:powersync/src/powersync_update_notification.dart';
import 'package:powersync/src/streaming_sync.dart';
import 'package:sqlite_async/sqlite3_common.dart';
import 'package:sqlite_async/sqlite_async.dart';

import '../../bucket_storage.dart';
import '../../migrations.dart';
import '../../schema_helpers.dart';
import '../database_interface.dart';

import '../../abort_controller.dart';
import '../../connector.dart';
import '../../schema.dart';

/// TODO add worker implementation

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
  /// Broadcast stream that is notified of any table updates.
  ///
  /// Unlike in [SqliteDatabase.updates], the tables reported here are the
  /// higher-level views as defined in the [Schema], and exclude the low-level
  /// PowerSync tables.
  @override
  late final Stream<UpdateNotification> updates;

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
    AbstractDefaultSqliteOpenFactory<CommonDatabase> factory =
        PowerSyncOpenFactory(path: path);
    return PowerSyncDatabase.withFactory(factory, schema: schema);
  }

  /// Open a [PowerSyncDatabase] with a [PowerSyncOpenFactory].
  ///
  /// The factory determines which database file is opened, as well as any
  /// additional logic to run inside the database isolate before or after opening.
  ///
  /// Subclass [PowerSyncOpenFactory] to add custom logic to this process.
  factory PowerSyncDatabase.withFactory(
      AbstractDefaultSqliteOpenFactory<CommonDatabase> openFactory,
      {required Schema schema}) {
    final db = SqliteDatabase.withFactory(openFactory, maxReaders: 1);
    return PowerSyncDatabase.withDatabase(schema: schema, database: db);
  }

  /// Open a PowerSyncDatabase on an existing [SqliteDatabase].
  ///
  /// Migrations are run on the database when this constructor is called.
  PowerSyncDatabase.withDatabase(
      {required Schema schema, required SqliteDatabase database}) {
    super.database = database;
    super.schema = schema;
    isInitialized = _init();
  }

  Future<void> _init() async {
    // TODO a nice way to extend this common logic in Dart
    statusStream = statusStreamController.stream;
    updates = database.updates
        .map((update) =>
            PowerSyncUpdateNotification.fromUpdateNotification(update))
        .where((update) => update.isNotEmpty)
        .cast<UpdateNotification>();
    await database.initialize();
    await migrations.migrate(database);
    // Update schema
    database.computeWithDatabase((db) async => updateSchema(db, schema));
  }

  @override
  bool get closed {
    // TODO
    return false;
  }

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

    final db = await database.openFactory
        .open(SqliteOpenOptions(primaryConnection: false, readOnly: false));
    final storage = BucketStorage(db);
    final sync = StreamingSyncImplementation(
        adapter: storage,
        credentialsCallback: connector.getCredentialsCached,
        invalidCredentialsCallback: connector.fetchCredentials,
        uploadCrud: () => connector.uploadData(this),
        updateStream: updates,
        retryDelay: Duration(seconds: 3));
    sync.streamingSync();
  }

  /// Close the database, releasing resources.
  ///
  /// Also [disconnect]s any active connection.
  ///
  /// Once close is called, this connection cannot be used again - a new one
  /// must be constructed.
  @override
  Future<void> close() async {
    // Don't close in the middle of the initialization process.
    await isInitialized;
    // Disconnect any active sync connection.
    await disconnect();

    // TODO close DB
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
}
