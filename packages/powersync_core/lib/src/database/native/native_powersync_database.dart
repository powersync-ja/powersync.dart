import 'dart:async';
import 'dart:isolate';
import 'package:meta/meta.dart';

import 'package:http/http.dart' as http;
import 'package:logging/logging.dart';
import 'package:powersync_core/src/abort_controller.dart';
import 'package:powersync_core/src/bucket_storage.dart';
import 'package:powersync_core/src/connector.dart';
import 'package:powersync_core/src/database/powersync_database.dart';
import 'package:powersync_core/src/database/powersync_db_mixin.dart';
import 'package:powersync_core/src/isolate_completer.dart';
import 'package:powersync_core/src/log.dart';
import 'package:powersync_core/src/log_internal.dart';
import 'package:powersync_core/src/open_factory/abstract_powersync_open_factory.dart';
import 'package:powersync_core/src/open_factory/native/native_open_factory.dart';
import 'package:powersync_core/src/schema.dart';
import 'package:powersync_core/src/streaming_sync.dart';
import 'package:powersync_core/src/sync_status.dart';
import 'package:sqlite_async/sqlite3_common.dart';
import 'package:sqlite_async/sqlite_async.dart';

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
    return PowerSyncDatabaseImpl.withFactory(factory,
        schema: schema, maxReaders: maxReaders, logger: logger);
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
    final db = SqliteDatabase.withFactory(openFactory, maxReaders: maxReaders);
    return PowerSyncDatabaseImpl.withDatabase(
        schema: schema, database: db, logger: logger);
  }

  /// Open a PowerSyncDatabase on an existing [SqliteDatabase].
  ///
  /// Migrations are run on the database when this constructor is called.
  ///
  /// [logger] defaults to [autoLogger], which logs to the console in debug builds.s
  PowerSyncDatabaseImpl.withDatabase(
      {required this.schema, required this.database, Logger? logger}) {
    this.logger = logger ?? autoLogger;
    isInitialized = baseInit();
  }

  @override
  @internal
  Future<void> connectInternal({
    required PowerSyncBackendConnector connector,
    required Duration crudThrottleTime,
    required AbortController abort,
    Map<String, dynamic>? params,
  }) async {
    await initialize();
    final dbRef = database.isolateConnectionFactory();

    Isolate? isolate;
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
      if (isolate != null) {
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

    receiveMessages.listen((data) async {
      if (data is List) {
        String action = data[0] as String;
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
          final port = initPort = data[1] as SendPort;
          hasInitPort.complete();
          var crudStream =
              database.onChange(['ps_crud'], throttle: crudThrottleTime);
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
    });

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

    // Spawning the isolate can't be interrupted
    isolate = await Isolate.spawn(
      _syncIsolate,
      _PowerSyncDatabaseIsolateArgs(
          receiveMessages.sendPort, dbRef, retryDelay, clientParams),
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
  final Duration retryDelay;
  final Map<String, dynamic>? parameters;

  _PowerSyncDatabaseIsolateArgs(
      this.sPort, this.dbRef, this.retryDelay, this.parameters);
}

Future<void> _syncIsolate(_PowerSyncDatabaseIsolateArgs args) async {
  final sPort = args.sPort;
  final rPort = ReceivePort();
  StreamController<String> crudUpdateController = StreamController.broadcast();
  final upstreamDbClient = args.dbRef.upstreamPort.open();

  CommonDatabase? db;
  final Mutex mutex = args.dbRef.mutex.open();
  StreamingSyncImplementation? openedStreamingSync;
  StreamSubscription<void>? localUpdatesSubscription;

  Future<void> shutdown() async {
    localUpdatesSubscription?.cancel();
    db?.dispose();
    crudUpdateController.close();
    upstreamDbClient.close();

    // The SyncSqliteConnection uses this mutex
    // It needs to be closed before killing the isolate
    // in order to free the mutex for other operations.
    await mutex.close();
    await openedStreamingSync?.abort();

    rPort.close();
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

  Future<PowerSyncCredentials?> loadCredentials() async {
    final r = IsolateResult<PowerSyncCredentials?>();
    sPort.send(['getCredentials', r.completer]);
    return r.future;
  }

  Future<void> invalidateCredentials() async {
    final r = IsolateResult<void>();
    sPort.send(['invalidateCredentials', r.completer]);
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
        credentialsCallback: loadCredentials,
        invalidCredentialsCallback: invalidateCredentials,
        uploadCrud: uploadCrud,
        crudUpdateTriggerStream: crudUpdateController.stream,
        retryDelay: args.retryDelay,
        client: http.Client(),
        syncParameters: args.parameters);
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

    localUpdatesSubscription = db!.updates.listen((event) {
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
    throw error;
  });
}
