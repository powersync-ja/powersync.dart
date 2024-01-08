import 'dart:async';
import 'dart:isolate';

import 'package:logging/logging.dart';
import 'package:sqlite_async/sqlite3.dart' as sqlite;
import 'package:sqlite_async/sqlite_async.dart';
import '../../open_factory/open_factory_interface.dart';
import '../../open_factory/native/native_open_factory.dart';
import '../database_interface.dart';

import '../../abort_controller.dart';
import '../../bucket_storage.dart';
import '../../connector.dart';
import '../../isolate_completer.dart';
import '../../log.dart';
import '../../powersync_update_notification.dart';
import '../../schema.dart';
import '../../schema_helpers.dart';
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
  /// Schema used for the local database.
  final Schema schema;

  /// The underlying database.
  ///
  /// For the most part, behavior is the same whether querying on the underlying
  /// database, or on [PowerSyncDatabase]. The main difference is in update notifications:
  /// the underlying database reports updates to the underlying tables, while
  /// [PowerSyncDatabase] reports updates to the higher-level views.
  final SqliteDatabase database;

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
      int maxReaders = SqliteDatabase.defaultMaxReaders,
      @Deprecated("Use [PowerSyncDatabase.withFactory] instead")
      // ignore: deprecated_member_use_from_same_package
      SqliteConnectionSetup? sqliteSetup}) {
    // ignore: deprecated_member_use_from_same_package
    AbstractDefaultSqliteOpenFactory<sqlite.Database> factory =
        PowerSyncOpenFactory(path: path, sqliteSetup: sqliteSetup);
    return PowerSyncDatabase.withFactory(factory, schema: schema);
  }

  /// Open a [PowerSyncDatabase] with a [PowerSyncOpenFactory].
  ///
  /// The factory determines which database file is opened, as well as any
  /// additional logic to run inside the database isolate before or after opening.
  ///
  /// Subclass [PowerSyncOpenFactory] to add custom logic to this process.
  factory PowerSyncDatabase.withFactory(
      AbstractDefaultSqliteOpenFactory<sqlite.Database> openFactory,
      {required Schema schema,
      int maxReaders = SqliteDatabase.defaultMaxReaders}) {
    final db = SqliteDatabase.withFactory(openFactory, maxReaders: maxReaders);
    return PowerSyncDatabase.withDatabase(schema: schema, database: db);
  }

  /// Open a PowerSyncDatabase on an existing [SqliteDatabase].
  ///
  /// Migrations are run on the database when this constructor is called.
  PowerSyncDatabase.withDatabase(
      {required this.schema, required this.database}) {
    updates = database.updates
        .map((update) =>
            PowerSyncUpdateNotification.fromUpdateNotification(update))
        .where((update) => update.isNotEmpty)
        .cast<UpdateNotification>();
    initialized = _init();
  }

  Future<void> _init() async {
    statusStream = statusStreamController.stream;
    await database.initialize();
    // TODO use Rust SQLite extension
    // await database.execute('SELECT powersync_init()');
    await updateSchemaInIsolate(database, schema);
  }

  /// Wait for initialization to complete.
  ///
  /// While initializing is automatic, this helps to catch and report initialization errors.
  Future<void> initialize() {
    return initialized;
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
  connect({required PowerSyncBackendConnector connector}) async {
    // Disconnect if connected
    await disconnect();
    final disconnector = AbortController();
    disconnecter = disconnector;

    await initialized;
    final dbref = database.isolateConnectionFactory();
    ReceivePort rPort = ReceivePort();
    StreamSubscription? updateSubscription;
    rPort.listen((data) async {
      if (data is List) {
        String action = data[0];
        if (action == "getCredentials") {
          await (data[1] as PortCompleter).handle(() async {
            final token = await connector.getCredentialsCached();
            log.fine('Credentials: $token');
            return token;
          });
        } else if (action == "invalidateCredentials") {
          log.fine('Refreshing credentials');
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
          _setStatus(SyncStatus(
              connected: false, lastSyncedAt: currentStatus.lastSyncedAt));
          rPort.close();
          updateSubscription?.cancel();
        } else if (action == 'log') {
          LogRecord record = data[1];
          log.log(
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
      log.severe('Sync Isolate error', message);

      // Reconnect
      connect(connector: connector);
    });

    disconnected() {
      disconnecter?.completeAbort();
      disconnecter = null;
      rPort.close();
    }

    var exitPort = ReceivePort();
    exitPort.listen((message) {
      log.fine('Sync Isolate exit');
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

  void _setStatus(SyncStatus status) {
    if (status != currentStatus) {
      currentStatus = status;
      statusStreamController.add(status);
    }
  }

  /// A connection factory that can be passed to different isolates.
  ///
  /// Use this to access the database in background isolates.
  IsolateConnectionFactory isolateConnectionFactory() {
    return database.isolateConnectionFactory();
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
    await initialized;
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
    await initialized;
    return database.readLock(callback,
        debugContext: debugContext, lockTimeout: lockTimeout);
  }

  /// Takes a global lock, without starting a transaction.
  ///
  /// In most cases, [writeTransaction] should be used instead.
  @override
  Future<T> writeLock<T>(Future<T> Function(SqliteWriteContext tx) callback,
      {String? debugContext, Duration? lockTimeout}) async {
    await initialized;
    return database.writeLock(callback,
        debugContext: debugContext, lockTimeout: lockTimeout);
  }
}

class _PowerSyncDatabaseIsolateArgs {
  final SendPort sPort;
  final IsolateConnectionFactory dbRef;
  final Duration retryDelay;

  _PowerSyncDatabaseIsolateArgs(this.sPort, this.dbRef, this.retryDelay);
}

Future<void> _powerSyncDatabaseIsolate(
    _PowerSyncDatabaseIsolateArgs args) async {
  final sPort = args.sPort;
  ReceivePort rPort = ReceivePort();
  StreamController updateController = StreamController.broadcast();
  final upstreamDbClient = args.dbRef.upstreamPort.open();

  sqlite.Database? db;
  final mutex = args.dbRef.mutex.open();

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
        Isolate.current.kill();
      }
    }
  });
  Isolate.current.addOnExitListener(sPort, response: const ['close']);
  sPort.send(["init", rPort.sendPort]);

  // Is there a way to avoid the overhead if logging is not enabled?
  // This only takes effect in this isolate.
  Logger.root.level = Level.ALL;
  log.onRecord.listen((record) {
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

    final storage = BucketStorage(db!, mutex: mutex!);
    final sync = StreamingSyncImplementation(
        adapter: storage,
        credentialsCallback: loadCredentials,
        invalidCredentialsCallback: invalidateCredentials,
        uploadCrud: uploadCrud,
        updateStream: updateController.stream,
        retryDelay: args.retryDelay);
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
