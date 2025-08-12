import 'dart:async';
import 'dart:convert';
import 'dart:isolate';
import 'package:meta/meta.dart';

import 'package:http/http.dart' as http;
import 'package:logging/logging.dart';
import 'package:powersync_core/src/abort_controller.dart';
import 'package:powersync_core/src/sync/bucket_storage.dart';
import 'package:powersync_core/src/connector.dart';
import 'package:powersync_core/src/database/powersync_database.dart';
import 'package:powersync_core/src/database/powersync_db_mixin.dart';
import 'package:powersync_core/src/isolate_completer.dart';
import 'package:powersync_core/src/log.dart';
import 'package:powersync_core/src/log_internal.dart';
import 'package:powersync_core/src/open_factory/abstract_powersync_open_factory.dart';
import 'package:powersync_core/src/open_factory/native/native_open_factory.dart';
import 'package:powersync_core/src/schema.dart';
import 'package:powersync_core/src/sync/internal_connector.dart';
import 'package:powersync_core/src/sync/options.dart';
import 'package:powersync_core/src/sync/streaming_sync.dart';
import 'package:powersync_core/src/sync/sync_status.dart';
import 'package:sqlite_async/sqlite3_common.dart';
import 'package:sqlite_async/sqlite_async.dart';
// ignore: implementation_imports
import 'package:sqlite_async/src/native/native_isolate_mutex.dart';

/// A PowerSync managed database.
///
///Native implementation for [PowerSyncDatabase]
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
    DefaultSqliteOpenFactory factory =
        // ignore: deprecated_member_use_from_same_package
        PowerSyncOpenFactory(path: path, sqliteSetup: sqliteSetup);
    return PowerSyncDatabaseImpl.withFactory(
      factory,
      schema: schema,
      maxReaders: maxReaders,
      logger: logger,
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
    DefaultSqliteOpenFactory openFactory, {
    required Schema schema,
    int maxReaders = SqliteDatabase.defaultMaxReaders,
    Logger? logger,
  }) {
    final db = SqliteDatabase.withFactory(openFactory, maxReaders: maxReaders);
    return PowerSyncDatabaseImpl.withDatabase(
      schema: schema,
      database: db,
      logger: logger,
    );
  }

  /// Open a PowerSyncDatabase on an existing [SqliteDatabase].
  ///
  /// Migrations are run on the database when this constructor is called.
  ///
  /// [logger] defaults to [autoLogger], which logs to the console in debug builds.s
  PowerSyncDatabaseImpl.withDatabase({
    required this.schema,
    required this.database,
    Logger? logger,
  }) {
    this.logger = logger ?? autoLogger;
    isInitialized = baseInit();
  }

  @override
  @internal
  Future<void> connectInternal({
    required PowerSyncBackendConnector connector,
    required ResolvedSyncOptions options,
    required List<SubscribedStream> initiallyActiveStreams,
    required Stream<List<({String name, String parameters})>> activeStreams,
    required AbortController abort,
    required Zone asyncWorkZone,
  }) async {
    final dbRef = database.isolateConnectionFactory();

    bool triedSpawningIsolate = false;
    StreamSubscription<UpdateNotification>? crudUpdateSubscription;
    final receiveMessages = ReceivePort();
    final receiveUnhandledErrors = ReceivePort();
    final receiveExit = ReceivePort();

    SendPort? initPort;
    final hasInitPort = Completer<void>();
    final receivedIsolateExit = Completer<void>();

    Future<void> waitForShutdown() async {
      // Only complete the abortion signal after the isolate shuts down. This
      // ensures absolutely no trace of this sync iteration remains.
      if (triedSpawningIsolate) {
        await receivedIsolateExit.future;
      }

      // Cleanup
      crudUpdateSubscription?.cancel();
      receiveMessages.close();
      receiveUnhandledErrors.close();
      receiveExit.close();

      // Clear status apart from lastSyncedAt
      setStatus(SyncStatus(lastSyncedAt: currentStatus.lastSyncedAt));
      abort.completeAbort();
    }

    Future<void> close() async {
      initPort?.send(['close']);
      await waitForShutdown();
    }

    Future<void> handleMessage(Object? data) async {
      if (data is List) {
        String action = data[0] as String;
        if (action == "getCredentialsCached") {
          await (data[1] as PortCompleter).handle(() async {
            final token = await connector.getCredentialsCached();
            logger.fine('Credentials: $token');
            return token;
          });
        } else if (action == "prefetchCredentials") {
          logger.fine('Refreshing credentials');
          final invalidate = data[2] as bool;

          await (data[1] as PortCompleter).handle(() async {
            if (invalidate) {
              connector.invalidateCredentials();
            }
            return await connector.prefetchCredentials();
          });
        } else if (action == 'init') {
          final port = initPort = data[1] as SendPort;
          hasInitPort.complete();
          var crudStream = database
              .onChange(['ps_crud'], throttle: options.crudThrottleTime);
          crudUpdateSubscription = crudStream.listen((event) {
            port.send(['update']);
          });
        } else if (action == 'uploadCrud') {
          await (data[1] as PortCompleter).handle(() async {
            await connector.uploadData(this);
          });
        } else if (action == 'status') {
          final SyncStatus status = data[1] as SyncStatus;
          setStatus(status);
        } else if (action == 'log') {
          LogRecord record = data[1] as LogRecord;
          logger.log(
              record.level, record.message, record.error, record.stackTrace);
        }
      }
    }

    // This function is called in a Zone marking the connection lock as locked.
    // This is used to prevent reentrant calls to the lock (which would be a
    // deadlock). However, the lock is returned as soon as this function
    // returns - and handleMessage may run later. So, make sure we run those
    // callbacks in the parent zone.
    receiveMessages.listen(asyncWorkZone.bindUnaryCallback(handleMessage));

    receiveUnhandledErrors.listen((message) async {
      // Sample error:
      // flutter: [PowerSync] WARNING: 2023-06-28 16:34:11.566122: Sync Isolate error
      // flutter: [Connection closed while receiving data, #0      IOClient.send.<anonymous closure> (package:http/src/io_client.dart:76:13)
      // #1      Stream.handleError.<anonymous closure> (dart:async/stream.dart:929:16)
      // #2      _HandleErrorStream._handleError (dart:async/stream_pipe.dart:269:17)
      // #3      _ForwardingStreamSubscription._handleError (dart:async/stream_pipe.dart:157:13)
      // #4      _HttpClientResponse.listen.<anonymous closure> (dart:_http/http_impl.dart:707:16)
      // ...
      logger.severe('Sync Isolate error', message);

      // Fatal errors are enabled, so the isolate will exit soon, causing us to
      // complete the abort controller which will make the db mixin reconnect if
      // necessary. There's no need to reconnect manually.
    });

    // Don't spawn isolate if this operation was cancelled already.
    if (abort.aborted) {
      return waitForShutdown();
    }

    receiveExit.listen((message) {
      logger.fine('Sync Isolate exit');
      receivedIsolateExit.complete();
    });

    final crudMutex = group.crudMutex as SimpleMutex;
    final syncMutex = group.syncMutex as SimpleMutex;

    // Spawning the isolate can't be interrupted
    triedSpawningIsolate = true;
    await Isolate.spawn(
      _syncIsolate,
      _PowerSyncDatabaseIsolateArgs(
        receiveMessages.sendPort,
        dbRef,
        options,
        crudMutex.shared,
        syncMutex.shared,
        jsonEncode(schema),
      ),
      debugName: 'Sync ${database.openFactory.path}',
      onError: receiveUnhandledErrors.sendPort,
      errorsAreFatal: true,
      onExit: receiveExit.sendPort,
    );
    await hasInitPort.future;

    abort.onAbort.whenComplete(close);

    // Automatically complete the abort controller once the isolate exits.
    unawaited(waitForShutdown());
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

class _PowerSyncDatabaseIsolateArgs {
  final SendPort sPort;
  final IsolateConnectionFactory dbRef;
  final ResolvedSyncOptions options;
  final SerializedMutex crudMutex;
  final SerializedMutex syncMutex;
  final String schemaJson;

  _PowerSyncDatabaseIsolateArgs(
    this.sPort,
    this.dbRef,
    this.options,
    this.crudMutex,
    this.syncMutex,
    this.schemaJson,
  );
}

Future<void> _syncIsolate(_PowerSyncDatabaseIsolateArgs args) async {
  final sPort = args.sPort;
  final rPort = ReceivePort();
  StreamController<String> crudUpdateController = StreamController.broadcast();
  final upstreamDbClient = args.dbRef.upstreamPort.open();

  final crudMutex = args.crudMutex.open();
  final syncMutex = args.syncMutex.open();

  CommonDatabase? db;
  final Mutex mutex = args.dbRef.mutex.open();
  StreamingSyncImplementation? openedStreamingSync;
  StreamSubscription<void>? localUpdatesSubscription;

  Completer<void> shutdownCompleter = Completer();

  Future<void> shutdown() {
    if (!shutdownCompleter.isCompleted) {
      shutdownCompleter.complete(Future(() async {
        await openedStreamingSync?.abort();

        localUpdatesSubscription?.cancel();
        db?.dispose();
        crudUpdateController.close();
        upstreamDbClient.close();

        // The SyncSqliteConnection uses this mutex
        // It needs to be closed before killing the isolate
        // in order to free the mutex for other operations.
        await mutex.close();
        await crudMutex.close();
        await syncMutex.close();
        rPort.close();

        // TODO: If we closed our resources properly, this wouldn't be necessary...
        Isolate.current.kill();
      }));
    }

    return shutdownCompleter.future;
  }

  rPort.listen((message) async {
    if (message is List) {
      String action = message[0] as String;
      if (action == 'update') {
        if (!crudUpdateController.isClosed) {
          crudUpdateController.add('update');
        }
      } else if (action == 'close') {
        await shutdown();
      }
    }
  });
  sPort.send(['init', rPort.sendPort]);

  // Is there a way to avoid the overhead if logging is not enabled?
  // This only takes effect in this isolate.
  isolateLogger.level = Level.ALL;
  isolateLogger.onRecord.listen((record) {
    var copy = LogRecord(record.level, record.message, record.loggerName,
        record.error, record.stackTrace);
    sPort.send(['log', copy]);
  });

  Future<PowerSyncCredentials?> getCredentialsCached() async {
    final r = IsolateResult<PowerSyncCredentials?>();
    sPort.send(['getCredentialsCached', r.completer]);
    return r.future;
  }

  Future<PowerSyncCredentials?> prefetchCredentials(
      {required bool invalidate}) async {
    final r = IsolateResult<PowerSyncCredentials?>();
    sPort.send(['prefetchCredentials', r.completer, invalidate]);
    return r.future;
  }

  Future<void> uploadCrud() async {
    final r = IsolateResult<void>();
    sPort.send(['uploadCrud', r.completer]);
    return r.future;
  }

  runZonedGuarded(() async {
    db = args.dbRef.openFactory
        .open(SqliteOpenOptions(primaryConnection: false, readOnly: false));
    final connection = SyncSqliteConnection(db!, mutex);

    final storage = BucketStorage(connection);
    final sync = StreamingSyncImplementation(
      adapter: storage,
      schemaJson: args.schemaJson,
      connector: InternalConnector(
        getCredentialsCached: getCredentialsCached,
        prefetchCredentials: prefetchCredentials,
        uploadCrud: uploadCrud,
      ),
      crudUpdateTriggerStream: crudUpdateController.stream,
      options: args.options,
      client: http.Client(),
      crudMutex: crudMutex,
      syncMutex: syncMutex,
    );
    openedStreamingSync = sync;
    sync.streamingSync();
    sync.statusStream.listen((event) {
      sPort.send(['status', event]);
    });

    Timer? updateDebouncer;
    Set<String> updatedTables = {};

    void maybeFireUpdates() {
      // Only fire updates when we're not in a transaction
      if (updatedTables.isNotEmpty && db?.autocommit == true) {
        upstreamDbClient.fire(UpdateNotification(updatedTables));
        updatedTables.clear();
        updateDebouncer?.cancel();
        updateDebouncer = null;
      }
    }

    localUpdatesSubscription = db!.updatesSync.listen((event) {
      updatedTables.add(event.tableName);

      updateDebouncer ??=
          Timer(const Duration(milliseconds: 1), maybeFireUpdates);
    });
  }, (error, stack) async {
    // Properly dispose the database if an uncaught error occurs.
    // Unfortunately, this does not handle disposing while the database is opening.
    // This should be rare - any uncaught error is a bug. And in most cases,
    // it should occur after the database is already open.
    await shutdown();
    Error.throwWithStackTrace(error, stack);
  });
}
