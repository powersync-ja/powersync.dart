import 'dart:async';
import 'dart:isolate';

import 'package:logging/logging.dart';
import 'package:powersync/src/log_internal.dart';
import 'package:sqlite_async/sqlite3_common.dart';
import 'package:sqlite_async/sqlite_async.dart';

import 'abort_controller.dart';
import 'bucket_storage.dart';
import 'connector.dart';
import 'crud.dart';
import 'isolate_completer.dart';
import 'log.dart';
import 'open_factory.dart';
import 'powersync_update_notification.dart';
import 'schema.dart';
import 'schema_logic.dart';
import 'streaming_sync.dart';
import 'sync_status.dart';

/// A PowerSync managed database.
///
/// Use one instance per database file.
///
/// Use [PowerSyncDatabase.connect] to connect to the PowerSync service,
/// to keep the local database in sync with the remote database.
///
/// All changes to local tables are automatically recorded, whether connected
/// or not. Once connected, the changes are uploaded.
class PowerSyncDatabase with SqliteQueries implements SqliteConnection {
  /// Schema used for the local database.
  Schema schema;

  /// The underlying database.
  ///
  /// For the most part, behavior is the same whether querying on the underlying
  /// database, or on [PowerSyncDatabase]. The main difference is in update notifications:
  /// the underlying database reports updates to the underlying tables, while
  /// [PowerSyncDatabase] reports updates to the higher-level views.
  final SqliteDatabase database;

  /// Current connection status.
  SyncStatus currentStatus = const SyncStatus();

  /// Use this stream to subscribe to connection status updates.
  late final Stream<SyncStatus> statusStream;

  final StreamController<SyncStatus> _statusStreamController =
      StreamController<SyncStatus>.broadcast();

  /// Broadcast stream that is notified of any table updates.
  ///
  /// Unlike in [SqliteDatabase.updates], the tables reported here are the
  /// higher-level views as defined in the [Schema], and exclude the low-level
  /// PowerSync tables.
  @override
  late final Stream<UpdateNotification> updates;

  /// Delay between retrying failed requests.
  /// Defaults to 5 seconds.
  /// Only has an effect if changed before calling [connect].
  Duration retryDelay = const Duration(seconds: 5);

  late Future<void> _initialized;

  /// null when disconnected, present when connecting or connected
  AbortController? _disconnecter;

  /// Use to prevent multiple connections from being opened concurrently
  final Mutex _connectMutex = Mutex();

  /// The Logger used by this [PowerSyncDatabase].
  ///
  /// The default is [autoLogger], which logs to the console in debug builds.
  /// Use [debugLogger] to always log to the console.
  /// Use [attachedLogger] to propagate logs to [Logger.root] for custom logging.
  late final Logger logger;

  Map<String, dynamic>? clientParams;

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
  factory PowerSyncDatabase(
      {required Schema schema,
      required String path,
      int maxReaders = SqliteDatabase.defaultMaxReaders,
      Logger? logger,
      @Deprecated("Use [PowerSyncDatabase.withFactory] instead.")
      // ignore: deprecated_member_use_from_same_package
      SqliteConnectionSetup? sqliteSetup}) {
    // ignore: deprecated_member_use_from_same_package
    var factory = PowerSyncOpenFactory(path: path, sqliteSetup: sqliteSetup);
    return PowerSyncDatabase.withFactory(factory,
        schema: schema, logger: logger);
  }

  /// Open a [PowerSyncDatabase] with a [PowerSyncOpenFactory].
  ///
  /// The factory determines which database file is opened, as well as any
  /// additional logic to run inside the database isolate before or after opening.
  ///
  /// Subclass [PowerSyncOpenFactory] to add custom logic to this process.
  ///
  /// [logger] defaults to [autoLogger], which logs to the console in debug builds.
  factory PowerSyncDatabase.withFactory(
    PowerSyncOpenFactory openFactory, {
    required Schema schema,
    int maxReaders = SqliteDatabase.defaultMaxReaders,
    Logger? logger,
  }) {
    final db = SqliteDatabase.withFactory(openFactory, maxReaders: maxReaders);
    return PowerSyncDatabase.withDatabase(
        schema: schema, database: db, logger: logger);
  }

  /// Open a PowerSyncDatabase on an existing [SqliteDatabase].
  ///
  /// Migrations are run on the database when this constructor is called.
  ///
  /// [logger] defaults to [autoLogger], which logs to the console in debug builds.
  PowerSyncDatabase.withDatabase({
    required this.schema,
    required this.database,
    Logger? logger,
  }) {
    if (logger != null) {
      this.logger = logger;
    } else {
      this.logger = autoLogger;
    }

    updates = database.updates
        .map((update) =>
            PowerSyncUpdateNotification.fromUpdateNotification(update))
        .where((update) => update.isNotEmpty)
        .cast<UpdateNotification>();
    _initialized = _init();
  }

  Future<void> _init() async {
    statusStream = _statusStreamController.stream;
    await database.initialize();
    await database.execute('SELECT powersync_init()');
    await updateSchema(schema);
    await _updateHasSynced();
  }

  /// Replace the schema with a new version.
  /// This is for advanced use cases - typically the schema should just be
  /// specified once in the constructor.
  ///
  /// Cannot be used while connected - this should only be called before [connect].
  Future<void> updateSchema(Schema schema) async {
    if (_disconnecter != null) {
      throw AssertionError('Cannot update schema while connected');
    }
    this.schema = schema;
    await updateSchemaInIsolate(database, schema);
  }

  /// Wait for initialization to complete.
  ///
  /// While initializing is automatic, this helps to catch and report initialization errors.
  Future<void> initialize() {
    return _initialized;
  }

  Future<void> _updateHasSynced() async {
    const syncedSQL =
        'SELECT 1 FROM ps_buckets WHERE last_applied_op > 0 LIMIT 1';

    // Query the database to see if any data has been synced.
    final result = await database.execute(syncedSQL);
    final hasSynced = result.rows.isNotEmpty;

    if (hasSynced != currentStatus.hasSynced) {
      final status = SyncStatus(hasSynced: hasSynced);
      _setStatus(status);
    }
  }

  ///
  /// returns a [Future] which will resolve once the first full sync has completed.
  ///
  Future<void> waitForFirstSync() async {
    if (currentStatus.hasSynced ?? false) {
      return;
    }
    await for (final result in statusStream) {
      if (result.hasSynced ?? false) {
        break;
      }
    }
  }

  @override
  bool get closed {
    return database.closed;
  }

  /// Connect to the PowerSync service, and keep the databases in sync.
  ///
  /// The connection is automatically re-opened if it fails for any reason.
  ///
  /// Status changes are reported on [statusStream].
  Future<void> connect(
      {required PowerSyncBackendConnector connector,

      /// Throttle time between CRUD operations
      /// Defaults to 10 milliseconds.
      Duration crudThrottleTime = const Duration(milliseconds: 10),
      Map<String, dynamic>? params}) async {
    Zone current = Zone.current;

    Future<void> reconnect() {
      return _connectMutex.lock(() => _connect(
          connector: connector,
          crudThrottleTime: crudThrottleTime,
          // The reconnect function needs to run in the original zone,
          // to avoid recursive lock errors.
          reconnect: current.bindCallback(reconnect),
          params: params));
    }

    await reconnect();
  }

  Future<void> _connect(
      {required PowerSyncBackendConnector connector,
      required Duration crudThrottleTime,
      required Future<void> Function() reconnect,
      Map<String, dynamic>? params}) async {
    clientParams = params;
    await initialize();

    // Disconnect if connected
    await disconnect();
    final disconnector = AbortController();
    _disconnecter = disconnector;

    await _initialized;
    final dbref = database.isolateConnectionFactory();
    ReceivePort rPort = ReceivePort();
    StreamSubscription? updateSubscription;
    rPort.listen((data) async {
      if (data is List) {
        String action = data[0];
        if (action == "getCredentials") {
          await (data[1] as PortCompleter).handle(() async {
            final token = await connector.getCredentialsCached();
            logger.fine('Credentials: $token');
            return token;
          });
        } else if (action == "invalidateCredentials") {
          logger.fine('Refreshing credentials');
          await (data[1] as PortCompleter).handle(() async {
            await connector.prefetchCredentials();
          });
        } else if (action == 'init') {
          SendPort port = data[1];
          var throttled =
              UpdateNotification.throttleStream(updates, crudThrottleTime);
          updateSubscription = throttled.listen((event) {
            port.send(['update']);
          });
          disconnector.onAbort.then((_) {
            port.send(['close']);
          }).ignore();
        } else if (action == 'uploadCrud') {
          await (data[1] as PortCompleter).handle(() async {
            await connector.uploadData(this);
          });
        } else if (action == 'status') {
          final SyncStatus status = data[1];
          _setStatus(status);
        } else if (action == 'close') {
          // Clear status apart from lastSyncedAt
          _setStatus(SyncStatus(lastSyncedAt: currentStatus.lastSyncedAt));
          rPort.close();
          updateSubscription?.cancel();
        } else if (action == 'log') {
          LogRecord record = data[1];
          logger.log(
              record.level, record.message, record.error, record.stackTrace);
        }
      }
    });

    var errorPort = ReceivePort();
    errorPort.listen((message) async {
      // Sample error:
      // flutter: [PowerSync] WARNING: 2023-06-28 16:34:11.566122: Sync Isolate error
      // flutter: [Connection closed while receiving data, #0      IOClient.send.<anonymous closure> (package:http/src/io_client.dart:76:13)
      // #1      Stream.handleError.<anonymous closure> (dart:async/stream.dart:929:16)
      // #2      _HandleErrorStream._handleError (dart:async/stream_pipe.dart:269:17)
      // #3      _ForwardingStreamSubscription._handleError (dart:async/stream_pipe.dart:157:13)
      // #4      _HttpClientResponse.listen.<anonymous closure> (dart:_http/http_impl.dart:707:16)
      // ...
      logger.severe('Sync Isolate error', message);

      // Reconnect
      // Use the param like this instead of directly calling connect(), to avoid recursive
      // locks in some edge cases.
      reconnect();
    });

    disconnected() {
      _disconnecter?.completeAbort();
      _disconnecter = null;
      rPort.close();
      // Clear status apart from lastSyncedAt
      _setStatus(SyncStatus(lastSyncedAt: currentStatus.lastSyncedAt));
    }

    var exitPort = ReceivePort();
    exitPort.listen((message) {
      logger.fine('Sync Isolate exit');
      disconnected();
    });

    if (_disconnecter?.aborted == true) {
      disconnected();
      return;
    }

    Isolate.spawn(
        _powerSyncDatabaseIsolate,
        _PowerSyncDatabaseIsolateArgs(
            rPort.sendPort, dbref, retryDelay, clientParams),
        debugName: 'PowerSyncDatabase',
        onError: errorPort.sendPort,
        onExit: exitPort.sendPort);
  }

  void _setStatus(SyncStatus status) {
    if (status != currentStatus) {
      currentStatus = status.copyWith(
          hasSynced: status.hasSynced ?? status.lastSyncedAt != null);
      _statusStreamController.add(currentStatus);
    }
  }

  /// Close the sync connection.
  ///
  /// Use [connect] to connect again.
  Future<void> disconnect() async {
    if (_disconnecter != null) {
      await _disconnecter!.abort();
    }
  }

  /// Disconnect and clear the database.
  ///
  /// Use this when logging out.
  ///
  /// The database can still be queried after this is called, but the tables
  /// would be empty.
  ///
  /// To preserve data in local-only tables, set [clearLocal] to false.
  Future<void> disconnectAndClear({bool clearLocal = true}) async {
    await disconnect();

    await writeTransaction((tx) async {
      await tx.execute('DELETE FROM ps_oplog');
      await tx.execute('DELETE FROM ps_crud');
      await tx.execute('DELETE FROM ps_buckets');
      await tx.execute('DELETE FROM ps_untyped');

      final tableGlob = clearLocal ? 'ps_data_*' : 'ps_data__*';
      final existingTableRows = await tx.getAll(
          "SELECT name FROM sqlite_master WHERE type='table' AND name GLOB ?",
          [tableGlob]);

      for (var row in existingTableRows) {
        await tx.execute('DELETE FROM ${quoteIdentifier(row['name'])}');
      }
    });
  }

  @Deprecated('Use [disconnectAndClear] instead.')
  Future<void> disconnectedAndClear() async {
    await disconnectAndClear();
  }

  /// Whether a connection to the PowerSync service is currently open.
  bool get connected {
    return currentStatus.connected;
  }

  /// A connection factory that can be passed to different isolates.
  ///
  /// Use this to access the database in background isolates.
  IsolateConnectionFactory isolateConnectionFactory() {
    return database.isolateConnectionFactory();
  }

  /// Get upload queue size estimate and count.
  Future<UploadQueueStats> getUploadQueueStats(
      {bool includeSize = false}) async {
    if (includeSize) {
      final row = await getOptional(
          'SELECT SUM(cast(data as blob) + 20) as size, count(*) as count FROM ps_crud');
      return UploadQueueStats(
          count: row?['count'] ?? 0, size: row?['size'] ?? 0);
    } else {
      final row = await getOptional('SELECT count(*) as count FROM ps_crud');
      return UploadQueueStats(count: row?['count'] ?? 0);
    }
  }

  /// Get a batch of crud data to upload.
  ///
  /// Returns null if there is no data to upload.
  ///
  /// Use this from the [PowerSyncBackendConnector.uploadData]` callback.
  ///
  /// Once the data have been successfully uploaded, call [CrudBatch.complete] before
  /// requesting the next batch.
  ///
  /// Use [limit] to specify the maximum number of updates to return in a single
  /// batch.
  ///
  /// This method does include transaction ids in the result, but does not group
  /// data by transaction. One batch may contain data from multiple transactions,
  /// and a single transaction may be split over multiple batches.
  Future<CrudBatch?> getCrudBatch({limit = 100}) async {
    final rows = await getAll(
        'SELECT id, tx_id, data FROM ps_crud ORDER BY id ASC LIMIT ?',
        [limit + 1]);
    List<CrudEntry> all = [for (var row in rows) CrudEntry.fromRow(row)];

    var haveMore = false;
    if (all.length > limit) {
      all.removeLast();
      haveMore = true;
    }
    if (all.isEmpty) {
      return null;
    }
    final last = all[all.length - 1];
    return CrudBatch(
        crud: all,
        haveMore: haveMore,
        complete: ({String? writeCheckpoint}) async {
          await writeTransaction((db) async {
            await db
                .execute('DELETE FROM ps_crud WHERE id <= ?', [last.clientId]);
            if (writeCheckpoint != null &&
                await db.getOptional('SELECT 1 FROM ps_crud LIMIT 1') == null) {
              await db.execute(
                  'UPDATE ps_buckets SET target_op = $writeCheckpoint WHERE name=\'\$local\'');
            } else {
              await db.execute(
                  'UPDATE ps_buckets SET target_op = $maxOpId WHERE name=\'\$local\'');
            }
          });
        });
  }

  /// Get the next recorded transaction to upload.
  ///
  /// Returns null if there is no data to upload.
  ///
  /// Use this from the [PowerSyncBackendConnector.uploadData]` callback.
  ///
  /// Once the data have been successfully uploaded, call [CrudTransaction.complete] before
  /// requesting the next transaction.
  ///
  /// Unlike [getCrudBatch], this only returns data from a single transaction at a time.
  /// All data for the transaction is loaded into memory.
  Future<CrudTransaction?> getNextCrudTransaction() async {
    return await readTransaction((tx) async {
      final first = await tx.getOptional(
          'SELECT id, tx_id, data FROM ps_crud ORDER BY id ASC LIMIT 1');
      if (first == null) {
        return null;
      }
      final int? txId = first['tx_id'];
      List<CrudEntry> all;
      if (txId == null) {
        all = [CrudEntry.fromRow(first)];
      } else {
        final rows = await tx.getAll(
            'SELECT id, tx_id, data FROM ps_crud WHERE tx_id = ? ORDER BY id ASC',
            [txId]);
        all = [for (var row in rows) CrudEntry.fromRow(row)];
      }

      final last = all[all.length - 1];

      return CrudTransaction(
          transactionId: txId,
          crud: all,
          complete: ({String? writeCheckpoint}) async {
            await writeTransaction((db) async {
              await db.execute(
                  'DELETE FROM ps_crud WHERE id <= ?', [last.clientId]);
              if (writeCheckpoint != null &&
                  await db.getOptional('SELECT 1 FROM ps_crud LIMIT 1') ==
                      null) {
                await db.execute(
                    'UPDATE ps_buckets SET target_op = $writeCheckpoint WHERE name=\'\$local\'');
              } else {
                await db.execute(
                    'UPDATE ps_buckets SET target_op = $maxOpId WHERE name=\'\$local\'');
              }
            });
          });
    });
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
    await _initialized;
    // Disconnect any active sync connection.
    await disconnect();
    // Now we can close the database
    await database.close();
  }

  /// Takes a read lock, without starting a transaction.
  ///
  /// In most cases, [readTransaction] should be used instead.
  @override
  Future<T> readLock<T>(Future<T> Function(SqliteReadContext tx) callback,
      {String? debugContext, Duration? lockTimeout}) async {
    await _initialized;
    return database.readLock(callback,
        debugContext: debugContext, lockTimeout: lockTimeout);
  }

  /// Takes a global lock, without starting a transaction.
  ///
  /// In most cases, [writeTransaction] should be used instead.
  @override
  Future<T> writeLock<T>(Future<T> Function(SqliteWriteContext tx) callback,
      {String? debugContext, Duration? lockTimeout}) async {
    await _initialized;
    return database.writeLock(callback,
        debugContext: debugContext, lockTimeout: lockTimeout);
  }

  @override
  Stream<ResultSet> watch(String sql,
      {List<Object?> parameters = const [],
      Duration throttle = const Duration(milliseconds: 30),
      Iterable<String>? triggerOnTables}) {
    if (triggerOnTables == null || triggerOnTables.isEmpty) {
      return super.watch(sql, parameters: parameters, throttle: throttle);
    }
    List<String> powersyncTables = [];
    for (String tableName in triggerOnTables) {
      powersyncTables.add(tableName);
      powersyncTables.add(_prefixTableNames(tableName, 'ps_data__'));
      powersyncTables.add(_prefixTableNames(tableName, 'ps_data_local__'));
    }
    return super.watch(sql,
        parameters: parameters,
        throttle: throttle,
        triggerOnTables: powersyncTables);
  }

  @override
  Future<bool> getAutoCommit() {
    return database.getAutoCommit();
  }

  String _prefixTableNames(String tableName, String prefix) {
    String prefixedString = tableName.replaceRange(0, 0, prefix);
    return prefixedString;
  }
}

class _PowerSyncDatabaseIsolateArgs {
  final SendPort sPort;
  final IsolateConnectionFactory dbRef;
  final Duration retryDelay;
  final Map<String, dynamic>? parameters;

  _PowerSyncDatabaseIsolateArgs(
      this.sPort, this.dbRef, this.retryDelay, this.parameters);
}

Future<void> _powerSyncDatabaseIsolate(
    _PowerSyncDatabaseIsolateArgs args) async {
  final sPort = args.sPort;
  ReceivePort rPort = ReceivePort();
  StreamController updateController = StreamController.broadcast();
  final upstreamDbClient = args.dbRef.upstreamPort.open();

  CommonDatabase? db;
  final mutex = args.dbRef.mutex.open();
  StreamingSyncImplementation? openedStreamingSync;

  rPort.listen((message) async {
    if (message is List) {
      String action = message[0];
      if (action == 'update') {
        updateController.add('update');
      } else if (action == 'close') {
        // This prevents any further transactions being opened, which would
        // eventually terminate the sync loop.
        await mutex.close();
        db?.dispose();
        db = null;
        updateController.close();
        upstreamDbClient.close();
        // Abort any open http requests, and wait for it to be closed properly
        await openedStreamingSync?.abort();
        // No kill the Isolate
        Isolate.current.kill();
      }
    }
  });
  Isolate.current.addOnExitListener(sPort, response: const ['close']);
  sPort.send(["init", rPort.sendPort]);

  // Is there a way to avoid the overhead if logging is not enabled?
  // This only takes effect in this isolate.
  isolateLogger.level = Level.ALL;
  isolateLogger.onRecord.listen((record) {
    var copy = LogRecord(record.level, record.message, record.loggerName,
        record.error, record.stackTrace);
    sPort.send(["log", copy]);
  });

  Future<PowerSyncCredentials?> loadCredentials() async {
    final r = IsolateResult<PowerSyncCredentials?>();
    sPort.send(["getCredentials", r.completer]);
    return r.future;
  }

  Future<void> invalidateCredentials() async {
    final r = IsolateResult<void>();
    sPort.send(["invalidateCredentials", r.completer]);
    return r.future;
  }

  Future<void> uploadCrud() async {
    final r = IsolateResult<void>();
    sPort.send(["uploadCrud", r.completer]);
    return r.future;
  }

  runZonedGuarded(() async {
    db = args.dbRef.openFactory
        .open(SqliteOpenOptions(primaryConnection: false, readOnly: false));

    final storage = BucketStorage(db!, mutex: mutex);
    final sync = StreamingSyncImplementation(
        adapter: storage,
        credentialsCallback: loadCredentials,
        invalidCredentialsCallback: invalidateCredentials,
        uploadCrud: uploadCrud,
        updateStream: updateController.stream,
        retryDelay: args.retryDelay,
        syncParameters: args.parameters);

    openedStreamingSync = sync;
    sync.streamingSync();
    sync.statusStream.listen((event) {
      sPort.send(['status', event]);
    });

    Timer? updateDebouncer;
    Set<String> updatedTables = {};

    void maybeFireUpdates() {
      if (updatedTables.isNotEmpty) {
        upstreamDbClient.fire(UpdateNotification(updatedTables));
        updatedTables.clear();
        updateDebouncer?.cancel();
        updateDebouncer = null;
      }
    }

    db!.updates.listen((event) {
      updatedTables.add(event.tableName);

      updateDebouncer ??=
          Timer(const Duration(milliseconds: 10), maybeFireUpdates);
    });
  }, (error, stack) {
    // Properly dispose the database if an uncaught error occurs.
    // Unfortunately, this does not handle disposing while the database is opening.
    // This should be rare - any uncaught error is a bug. And in most cases,
    // it should occur after the database is already open.
    db?.dispose();
    db = null;
    mutex.close();
    throw error;
  });
}
