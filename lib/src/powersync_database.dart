import 'dart:async';
import 'dart:isolate';

import 'package:logging/logging.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;

import './log.dart';
import './connection_pool.dart';
import './connector.dart';
import './background_database.dart';
import './sqlite_connection.dart';
import './bucket_storage.dart';
import './database_init.dart';
import './isolate_completer.dart';
import './mutex.dart';
import './schema.dart';
import './schema_logic.dart';
import './streaming_sync.dart';
import './throttle.dart';
import './crud.dart';

/// Advanced: Define custom setup for each SQLite connection.
class SqliteConnectionSetup {
  final FutureOr<void> Function() _setup;

  /// The setup parameter is called every time a database connection is opened.
  /// This can be used to configure dynamic library loading if required.
  const SqliteConnectionSetup(FutureOr<void> Function() setup) : _setup = setup;

  Future<void> setup() async {
    await _setup();
  }
}

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
  /// Database path.
  final String path;

  /// Schema used for the local database.
  final Schema schema;

  /// Maximum number of concurrent read transactions.
  final int maxReaders;

  /// Global lock to serialize write transactions.
  final Mutex mutex = Mutex.shared();

  /// Advanced: Custom logic to execute in each database isolate.
  final SqliteConnectionSetup? sqliteSetup;

  /// Use this stream to subscribe to notifications of updates to tables.
  @override
  late final Stream<TableUpdate> updates;

  /// Current connection status.
  SyncStatus currentStatus =
      const SyncStatus(connected: false, lastSyncedAt: null);

  /// Use this stream to subscribe to connection status updates.
  late final Stream<SyncStatus> statusStream;

  final StreamController<TableUpdate> _updatesController =
      StreamController.broadcast();

  final ReceivePort _eventsPort = ReceivePort();
  final StreamController<SyncStatus> _statusStreamController =
      StreamController<SyncStatus>.broadcast();

  late final SqliteConnectionImpl _internalConnection;
  late final SqliteConnectionPool _pool;
  late final Future<void> _initialized;
  late List<String> _initializeStatements;

  SendPort? _streamingSyncPort;

  /// Open a PowerSyncDatabase.
  ///
  /// Only a single PowerSyncDatabase per [path] should be opened at a time.
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
  /// Advanced: Use [sqliteSetup] to execute custom initialization logic in
  /// each database isolate.
  PowerSyncDatabase(
      {required this.schema,
      required this.path,
      this.maxReaders = 5,
      this.sqliteSetup}) {
    updates = _updatesController.stream;
    statusStream = _statusStreamController.stream;
    _internalConnection = _openPrimaryConnection(debugName: 'powersync-writer');
    _pool = SqliteConnectionPool(_dbref(),
        updates: updates,
        writeConnection: _internalConnection,
        debugName: 'powersync',
        maxReaders: maxReaders);

    _listenForEvents();

    _initialized = _init();
  }

  Future<void> _init() async {
    _initializeStatements =
        await _initializePrimaryDatabase(_internalConnection, mutex, schema);
  }

  /// Wait for initialization to complete.
  ///
  /// While initializing is automatic, this helps to catch and report initialization errors.
  Future<void> initialize() async {
    await _initialized;
  }

  void _listenForEvents() {
    TableUpdate? updates;

    _eventsPort.listen((message) async {
      if (message is List) {
        String type = message[0];
        if (type == 'update') {
          sqlite.SqliteUpdate event = message[1];
          String? friendlyName = friendlyTableName(event.tableName);
          if (friendlyName != null) {
            if (updates == null) {
              updates = TableUpdate({friendlyName});
            } else {
              updates = TableUpdate(
                  {for (var table in updates!.tables) table, friendlyName});
            }
          }
          mutex.lock(() async {
            if (updates != null) {
              _updatesController.add(updates!);
              updates = null;
            }
          });
        } else if (type == 'init-db') {
          PortCompleter<List<String>> completer = message[1];
          await completer.handle(() async {
            await _initialized;
            return _initializeStatements;
          });
        }
      }
    });
  }

  /// Connect to the PowerSync service, and keep the databases in sync.
  ///
  /// The connection is automatically re-opened if it fails for any reason.
  ///
  /// Status changes are reported on [statusStream].
  connect({required PowerSyncBackendConnector connector}) async {
    final dbref = _dbref();
    ReceivePort rPort = ReceivePort();
    disconnect();
    rPort.listen((data) async {
      if (data is List) {
        String action = data[0];
        if (action == "getCredentials") {
          await (data[1] as PortCompleter).handle(() async {
            final token = await connector.getCredentials();
            return token;
          });
        } else if (action == "invalidateCredentials") {
          await (data[1] as PortCompleter).handle(() async {
            await connector.refreshCredentials();
          });
        } else if (action == 'init') {
          SendPort port = data[1];
          _streamingSyncPort = port;
          updates
              .transform(throttleTransformer(const Duration(milliseconds: 10)))
              .listen((event) {
            port.send(['update']);
          });
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
        } else if (action == 'log') {
          LogRecord record = data[1];
          log.log(
              record.level, record.message, record.error, record.stackTrace);
        }
      }
    });

    Isolate.spawn(_powerSyncDatabaseIsolate,
        _PowerSyncDatabaseIsolateArgs(rPort.sendPort, dbref, mutex),
        debugName: 'PowerSyncDatabase');
  }

  void _setStatus(SyncStatus status) {
    if (status != currentStatus) {
      currentStatus = status;
      _statusStreamController.add(status);
    }
  }

  /// Close the sync connection.
  ///
  /// Use [connect] to connect again.
  void disconnect() {
    if (_streamingSyncPort != null) {
      _streamingSyncPort!.send(['close']);
      _streamingSyncPort = null;
    }
  }

  /// Disconnect and clear the database.
  ///
  /// Use this when logging out.
  ///
  /// The database can still be queried after this is called, but the tables
  /// would be empty.
  Future<void> disconnectedAndClear() async {
    disconnect();

    await writeTransaction((tx) async {
      await tx.execute('DELETE FROM ps_oplog WHERE 1');
      await tx.execute('DELETE FROM ps_crud WHERE 1');
      await tx.execute('DELETE FROM ps_buckets WHERE 1');

      final existingTableRows = await tx.getAll(
          "SELECT name FROM sqlite_master WHERE type='table' AND name GLOB 'ps_data_*'");

      for (var row in existingTableRows) {
        await tx.execute('DELETE FROM "${row['name']}" WHERE 1');
      }
    });
  }

  SqliteConnectionImpl _openPrimaryConnection({String? debugName}) {
    return SqliteConnectionImpl(_dbref(primary: true),
        updates: updates, debugName: debugName);
  }

  /// Advanced: Get a connection factory.
  ///
  /// This factory can be passed to other isolates, to allow querying from
  /// different isolates.
  SqliteConnectionFactory connectionFactory() {
    return _dbref();
  }

  SqliteConnectionFactory _dbref({bool primary = false}) {
    return SqliteConnectionFactory._(
        path: path,
        port: _eventsPort.sendPort,
        mutex: mutex,
        primary: primary,
        setup: sqliteSetup);
  }

  /// Whether a connection to the PowerSync service is currently open.
  bool get connected {
    return currentStatus.connected;
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
  Future<CrudBatch?> getCrudBatch({limit = 100}) async {
    final rows = await getAll(
        'SELECT id, data FROM ps_crud ORDER BY id ASC LIMIT ?', [limit + 1]);
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
        complete: () async {
          await writeTransaction((db) async {
            await db
                .execute('DELETE FROM ps_crud WHERE id <= ?', [last.clientId]);
            await db.execute(
                'UPDATE ps_buckets SET target_op = $maxOpId WHERE name=\'\$local\'');
          });
        });
  }

  /// Open a read-only transaction.
  ///
  /// Up to [maxReaders] read transactions can run concurrently.
  /// After that, read transactions are queued.
  ///
  /// Read transactions can run concurrently to a write transaction.
  ///
  /// Changes from any write transaction are not visible to read transactions
  /// started before it.
  @override
  Future<T> readTransaction<T>(
      Future<T> Function(SqliteReadContext tx) callback,
      {Duration? lockTimeout}) {
    return _pool.readTransaction(callback, lockTimeout: lockTimeout);
  }

  /// Open a read-write transaction.
  ///
  /// Only a single write transaction can run at a time - any concurrent
  /// transactions are queued.
  ///
  /// The write transaction is automatically committed when the callback finishes,
  /// or rolled back on any error.
  @override
  Future<T> writeTransaction<T>(
      Future<T> Function(SqliteWriteContext tx) callback,
      {Duration? lockTimeout}) {
    return _pool.writeTransaction(callback, lockTimeout: lockTimeout);
  }

  @override
  Future<T> readLock<T>(Future<T> Function(SqliteReadContext tx) callback,
      {Duration? lockTimeout}) {
    return _pool.readLock(callback, lockTimeout: lockTimeout);
  }

  @override
  Future<T> writeLock<T>(Future<T> Function(SqliteWriteContext tx) callback,
      {Duration? lockTimeout}) {
    return _pool.writeLock(callback, lockTimeout: lockTimeout);
  }
}

/// Stats of the local upload queue.
class UploadQueueStats {
  /// Number of records in the upload queue.
  int count;

  /// Size of the upload queue in bytes.
  int? size;

  UploadQueueStats({required this.count, this.size});

  @override
  String toString() {
    if (size == null) {
      return "UploadQueueStats<count: $count>";
    } else {
      return "UploadQueueStats<count: $count size: ${size! / 1024}kB>";
    }
  }
}

/// Advanced: Factory that can safely be serialized and sent to different isolates to
/// open connections in multiple isolates.
///
/// Not required in typical use cases.
class SqliteConnectionFactory {
  String path;
  SendPort port;
  Mutex mutex;
  bool primary;
  SqliteConnectionSetup? setup;

  SqliteConnectionFactory._(
      {required this.path,
      required this.port,
      required this.mutex,
      this.setup,
      this.primary = false});

  /// Open a SQLite database connection.
  /// A dedicated Isolate is spawned for running the actual queries.
  SqliteConnection openConnection(
      {String? debugName,
      Stream<TableUpdate>? updates,
      bool readOnly = false}) {
    return SqliteConnectionImpl(this,
        debugName: debugName, updates: updates, readOnly: readOnly);
  }

  /// Open a raw sqlite.Database, providing direct access to the SQLite APIs.
  ///
  /// The APIs are low-level, and does not include automatic app-level locking.
  /// Use with care - this can easily result in DATABASE_LOCKED or other errors.
  /// All operations on this database are synchronous, and blocks the current
  /// isolate.
  Future<sqlite.Database> openRawDatabase({bool readOnly = false}) async {
    if (setup != null) {
      await setup!.setup();
    }
    List<String> initializeStatements = [];
    if (!primary) {
      var initialized = IsolateResult<List<String>>();
      port.send(['init-db', initialized.completer]);
      initializeStatements = await initialized.future;
    }

    DatabaseInit ps;
    if (primary) {
      ps = DatabaseInitPrimary(path, mutex: mutex);
    } else {
      ps = DatabaseInit(path);
    }
    sqlite.OpenMode mode;
    if (primary) {
      mode = sqlite.OpenMode.readWriteCreate;
    } else if (readOnly) {
      mode = sqlite.OpenMode.readOnly;
    } else {
      mode = sqlite.OpenMode.readWrite;
    }

    final db = await ps.open(mode: mode);
    for (var statement in initializeStatements) {
      db.execute(statement);
    }

    db.updates.listen((event) {
      port.send(['update', event]);
    });
    return db;
  }
}

class _PowerSyncDatabaseIsolateArgs {
  SendPort sPort;
  SqliteConnectionFactory dbRef;
  Mutex mutex;

  _PowerSyncDatabaseIsolateArgs(this.sPort, this.dbRef, this.mutex);
}

Future<void> _powerSyncDatabaseIsolate(
    _PowerSyncDatabaseIsolateArgs args) async {
  final sPort = args.sPort;
  ReceivePort rPort = ReceivePort();
  StreamController updateController = StreamController.broadcast();

  sqlite.Database? db;
  rPort.listen((message) {
    if (message is List) {
      String action = message[0];
      if (action == 'update') {
        updateController.add('update');
      } else if (action == 'close') {
        db?.dispose();
        updateController.close();
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
    sPort.send(["log", record]);
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

  db = await args.dbRef.openRawDatabase();
  final storage = BucketStorage(db, mutex: args.mutex);
  final sync = StreamingSyncImplementation(
      adapter: storage,
      credentialsCallback: loadCredentials,
      invalidCredentialsCallback: invalidateCredentials,
      uploadCrud: uploadCrud,
      updateStream: updateController.stream
          .transform(throttleTransformer(const Duration(milliseconds: 10))));
  sync.streamingSync();
  sync.statusStream.listen((event) {
    sPort.send(['status', event]);
  });
}

Future<List<String>> _initializePrimaryDatabase(
    SqliteConnection asyncdb, Mutex mutex, Schema schema) async {
  return await asyncdb.computeWithDatabase((db) async {
    List<String> ops = updateSchema(db, schema);
    return ops;
  });
}
