import 'dart:async';
import 'dart:isolate';
import 'package:meta/meta.dart';

import 'package:http/http.dart' as http;
import 'package:logging/logging.dart';
import 'package:powersync/src/log_internal.dart';
import 'package:sqlite_async/sqlite3_common.dart';
import 'package:sqlite_async/sqlite_async.dart';
import '../../open_factory/abstract_powersync_open_factory.dart';
import '../../open_factory/native/native_open_factory.dart';
import '../abstract_powersync_database.dart';

import '../../abort_controller.dart';
import '../../bucket_storage.dart';
import '../../connector.dart';
import '../../isolate_completer.dart';
import '../../log.dart';
import '../../schema.dart';
import '../../schema_logic.dart';
import '../../streaming_sync.dart';
import '../../sync_status.dart';

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
  factory PowerSyncDatabase(
      {required Schema schema,
      required String path,
      int maxReaders = AbstractSqliteDatabase.defaultMaxReaders,
      Logger? logger,
      @Deprecated("Use [PowerSyncDatabase.withFactory] instead")
      // ignore: deprecated_member_use_from_same_package
      SqliteConnectionSetup? sqliteSetup}) {
    // ignore: deprecated_member_use_from_same_package
    DefaultSqliteOpenFactory factory =
        // ignore: deprecated_member_use_from_same_package
        PowerSyncOpenFactory(path: path, sqliteSetup: sqliteSetup);
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
  factory PowerSyncDatabase.withFactory(DefaultSqliteOpenFactory openFactory,
      {required Schema schema,
      int maxReaders = AbstractSqliteDatabase.defaultMaxReaders,
      Logger? logger}) {
    final db = SqliteDatabase.withFactory(openFactory, maxReaders: maxReaders);
    return PowerSyncDatabase.withDatabase(
        schema: schema, database: db, logger: logger);
  }

  /// Open a PowerSyncDatabase on an existing [SqliteDatabase].
  ///
  /// Migrations are run on the database when this constructor is called.
  ///
  /// [logger] defaults to [autoLogger], which logs to the console in debug builds.s
  PowerSyncDatabase.withDatabase(
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
          var throttled = UpdateNotification.throttleStream(
              updates, const Duration(milliseconds: 10));
          updateSubscription = throttled.listen((event) {
            port.send(['update']);
          });
          disconnecter?.onAbort.then((_) {
            port.send(['close']);
          }).ignore();
        } else if (action == 'uploadCrud') {
          await (data[1] as PortCompleter).handle(() async {
            await connector.uploadData(this);
          });
        } else if (action == 'status') {
          final SyncStatus status = data[1];
          setStatus(status);
        } else if (action == 'close') {
          setStatus(SyncStatus(
              connected: false, lastSyncedAt: currentStatus.lastSyncedAt));
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
      connect(connector: connector);
    });

    disconnected() {
      disconnecter?.completeAbort();
      disconnecter = null;
      rPort.close();
      // Clear status apart from lastSyncedAt
      setStatus(SyncStatus(lastSyncedAt: currentStatus.lastSyncedAt));
    }

    var exitPort = ReceivePort();
    exitPort.listen((message) {
      logger.fine('Sync Isolate exit');
      disconnected();
    });

    if (disconnecter?.aborted == true) {
      disconnected();
      return;
    }

    Isolate.spawn(_powerSyncDatabaseIsolate,
        _PowerSyncDatabaseIsolateArgs(rPort.sendPort, dbref, retryDelay),
        debugName: 'PowerSyncDatabase',
        onError: errorPort.sendPort,
        onExit: exitPort.sendPort);
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
    return updateSchemaInIsolate(database, schema);
  }
}

class _PowerSyncDatabaseIsolateArgs {
  final SendPort sPort;
  final AbstractIsolateConnectionFactory dbRef;
  final Duration retryDelay;

  _PowerSyncDatabaseIsolateArgs(this.sPort, this.dbRef, this.retryDelay);
}

Future<void> _powerSyncDatabaseIsolate(
    _PowerSyncDatabaseIsolateArgs args) async {
  final sPort = args.sPort;
  ReceivePort rPort = ReceivePort();
  StreamController updateController = StreamController.broadcast();
  final upstreamDbClient = args.dbRef.upstreamPort.open();

  CommonDatabase? db;
  final mutex = args.dbRef.mutex.open();

  rPort.listen((message) async {
    if (message is List) {
      String action = message[0];
      if (action == 'update') {
        updateController.add('update');
      } else if (action == 'close') {
        // This prevents any further transactions being opened, which would
        // eventually terminate the sync loop.
        // await mutex.close();
        db?.dispose();
        db = null;
        updateController.close();
        // upstreamDbClient.close();
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
    db = await args.dbRef.openFactory
        .open(SqliteOpenOptions(primaryConnection: false, readOnly: false));
    final connection = SyncSqliteConnection(db!, mutex);

    final storage = BucketStorage(connection);
    final sync = StreamingSyncImplementation(
        adapter: storage,
        credentialsCallback: loadCredentials,
        invalidCredentialsCallback: invalidateCredentials,
        uploadCrud: uploadCrud,
        updateStream: updateController.stream,
        retryDelay: args.retryDelay,
        client: http.Client());
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
    throw error;
  });
}
