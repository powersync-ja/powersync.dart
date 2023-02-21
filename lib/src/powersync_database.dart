import 'dart:async';
import 'dart:convert';
import 'dart:isolate';

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
import './thottle.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;

/// Use to define custom setup for each SQLite connection
class SqliteConnectionSetup {
  final FutureOr<void> Function() _setup;

  /// The setup parameter is called every time a database connection is opened.
  /// This can be used to configure dynamic library loading if required.
  const SqliteConnectionSetup(FutureOr<void> Function() setup) : _setup = setup;

  Future<void> setup() async {
    await _setup();
  }
}

/// A PowerSync managed database
class PowerSyncDatabase implements SqliteConnection {
  /// Database path
  final String path;
  final Schema schema;
  final SqliteConnectionSetup? sqliteSetup;

  /// Global lock to serialize write transactions
  final Mutex mutex = Mutex.shared();

  /// Use this stream to subscribe to notifications of updates to tables.
  late final Stream<TableUpdate> updates;

  /// Use this stream to subscribe to connection status updates.
  late final Stream<SyncStatus> statusStream;

  final StreamController<TableUpdate> _updatesController =
      StreamController.broadcast();

  final ReceivePort _eventsPort = ReceivePort();
  SyncStatus _status = const SyncStatus(connected: false, lastSyncedAt: null);
  final StreamController<SyncStatus> _statusStreamController =
      StreamController<SyncStatus>.broadcast();

  late final SqliteConnectionImpl _internalConnection;
  late final Future<void> _initialized;
  late List<String> _initializeStatements;

  SendPort? _streamingSyncPort;

  /// Open a PowerSyncDatabase.
  ///
  /// Only a single PowerSyncDatabase per file should be opened at a time.
  ///
  /// For concurrent queries, use `openConnection()` to open additional
  /// connections.
  PowerSyncDatabase(
      {required this.schema, required this.path, this.sqliteSetup}) {
    updates = _updatesController.stream;
    statusStream = _statusStreamController.stream;
    _internalConnection = _openPrimaryConnection();

    _listenForEvents();

    _initialized = _init();
  }

  Future<void> _init() async {
    _initializeStatements =
        await _initializePrimaryDatabase(_internalConnection, mutex, schema);
  }

  /// While initializing is automatic, waiting on the initialization allows for
  /// voids potential uncaught errors.
  Future<void> initialize() async {
    return _initialized;
  }

  void _listenForEvents() {
    Set<TableUpdate> updates = {};

    _eventsPort.listen((message) async {
      if (message is List) {
        String type = message[0];
        if (type == 'update') {
          sqlite.SqliteUpdate event = message[1];
          final re = RegExp(r"^objects__(.+)$");
          final match = re.firstMatch(event.tableName);
          if (match != null) {
            final name = match[1];
            final update = TableUpdate(name!);
            updates.add(update);
          }
          mutex.lock(() async {
            if (updates.isNotEmpty) {
              // TODO: throttle?
              for (var update in updates) {
                _updatesController.add(update);
              }

              updates = {};
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
  connect({required PowerSyncBackendConnector connector}) async {
    final dbref = _dbref();
    ReceivePort rPort = ReceivePort();
    if (_streamingSyncPort != null) {
      _streamingSyncPort!.send(['close']);
      _streamingSyncPort = null;
    }
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
          if (status != _status) {
            _status = status;
            _statusStreamController.add(status);
          }
        }
      }
    });

    Isolate.spawn(_powerSyncDatabaseIsolate,
        _PowerSyncDatabaseIsolateArgs(rPort.sendPort, dbref, mutex),
        debugName: 'PowerSyncDatabase');
  }

  /// Open a SQLite database connection.
  /// A dedicated Isolate is spawned for running the actual queries.
  SqliteConnection openConnection({String? debugName}) {
    return _dbref().openConnection(updates: updates, debugName: debugName);
  }

  SqliteConnectionImpl _openPrimaryConnection({String? debugName}) {
    return SqliteConnectionImpl(_dbref(primary: true),
        updates: updates, debugName: debugName);
  }

  /// Get a connection factory.
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

  bool get connected {
    return _status.connected;
  }

  /// Get upload queue size estimate and count.
  Future<UploadQueueStats> getUploadQueueStats(
      {bool includeSize = false}) async {
    if (includeSize) {
      final row = await _internalConnection.getOptional(
          'SELECT SUM(cast(data as blob) + 20) as size, count(*) as count FROM crud');
      return UploadQueueStats(
          count: row?['count'] ?? 0, size: row?['size'] ?? 0);
    } else {
      final row = await _internalConnection
          .getOptional('SELECT count(*) as count FROM crud');
      return UploadQueueStats(count: row?['count'] ?? 0);
    }
  }

  /// Get a batch of crud data to upload.
  /// Returns null if there is no data to upload.
  /// Use this from the `PowerSyncBackendConnector#uploadData()` callback.
  /// Once the data have been sucessfully uploaded, call `batch.complete()` before
  /// requesting the next batch.
  Future<CrudBatch?> getCrudBatch({limit = 100}) async {
    final rows = await _internalConnection.getAll(
        'SELECT id, data FROM crud ORDER BY id ASC LIMIT ?', [limit + 1]);
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
          await _internalConnection.writeTransaction((db) async {
            await db.execute('DELETE FROM crud WHERE id <= ?', [last.clientId]);
            await db.execute(
                'UPDATE buckets SET target_op = $maxOpId WHERE name=\'\$local\'');
          });
        });
  }

  @override
  Future<sqlite.ResultSet> execute(String sql,
      [List<Object?> parameters = const []]) {
    return _internalConnection.execute(sql, parameters);
  }

  @override
  Future<sqlite.Row> get(String sql, [List<Object?> parameters = const []]) {
    return _internalConnection.get(sql, parameters);
  }

  @override
  Future<sqlite.ResultSet> getAll(String sql,
      [List<Object?> parameters = const []]) {
    return _internalConnection.getAll(sql, parameters);
  }

  @override
  Future<sqlite.Row?> getOptional(String sql,
      [List<Object?> parameters = const []]) {
    return _internalConnection.getOptional(sql, parameters);
  }

  @override
  Future<T> readTransaction<T>(
      Future<T> Function(SqliteReadTransactionContext tx) callback,
      {Duration? lockTimeout}) {
    return _internalConnection.readTransaction(callback,
        lockTimeout: lockTimeout);
  }

  @override
  Stream<sqlite.ResultSet> watch(String sql,
      {List<Object?> parameters = const [],
      Duration throttle = const Duration(milliseconds: 30)}) {
    return _internalConnection.watch(sql,
        parameters: parameters, throttle: throttle);
  }

  @override
  Future<T> writeTransaction<T>(
      Future<T> Function(SqliteWriteTransactionContext tx) callback,
      {Duration? lockTimeout}) {
    return _internalConnection.writeTransaction(callback,
        lockTimeout: lockTimeout);
  }
}

class UploadQueueStats {
  /// Number of records in the upload queue
  int count;

  /// Size of the upload queue in bytes
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

/// Factory that can safely be serialized and sent to different isolates to
/// open connections in multiple isolates.
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
      {String? debugName, Stream<TableUpdate>? updates}) {
    return SqliteConnectionImpl(this, debugName: debugName, updates: updates);
  }

  /// Open a raw sqlite.Database, providing direct access to the SQLite APIs.
  /// The APIs are low-level, and does not include automatic app-level locking.
  /// Use with care - this can easily result in DATABASE_LOCKED or other errors.
  /// All operations on this database are synchronous, and blocks the current
  /// isolate.
  Future<sqlite.Database> openRawDatabase() async {
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
    final db = await ps.open();
    for (var statement in initializeStatements) {
      db.execute(statement);
    }

    db.updates.listen((event) {
      if (event.tableName.startsWith('objects_')) {
        port.send(['update', event]);
      }
    });
    return db;
  }
}

class TableUpdate {
  final String name;

  const TableUpdate(this.name);

  @override
  bool operator ==(Object other) {
    return other is TableUpdate && other.name == name;
  }

  @override
  int get hashCode {
    return name.hashCode;
  }

  @override
  String toString() {
    return "TableUpdate<$name>";
  }
}

enum UpdateType {
  /// Insert or replace a row. All non-null fields are included in the data.
  put('PUT'),
  // Update a row if it exists. All updated columns are included in the data.
  patch('PATCH'),
  // Delete a row if it exists.
  delete('DELETE');

  final String json;

  const UpdateType(this.json);

  String toJson() {
    return json;
  }

  static UpdateType? fromJson(String json) {
    switch (json) {
      case 'PUT':
        return put;
      case 'PATCH':
        return patch;
      case 'DELETE':
        return delete;
      default:
        return null;
    }
  }

  static UpdateType? fromJsonChecked(String json) {
    var v = fromJson(json);
    assert(v != null, "Unexpected updateType: $json");
    return v;
  }
}

class CrudEntry {
  int clientId;
  UpdateType op;
  String table;
  String id;
  Map<String, dynamic>? opData;

  CrudEntry(this.clientId, this.op, this.table, this.id, this.opData);

  factory CrudEntry.fromRow(sqlite.Row row) {
    final data = jsonDecode(row['data']);
    return CrudEntry(row['id'], UpdateType.fromJsonChecked(data['op'])!,
        data['type'], data['id'], data['data']);
  }

  Map<String, dynamic> toJson() {
    return {
      'op_id': clientId,
      'op': op.toJson(),
      'type': table,
      'id': id,
      'data': opData
    };
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
  rPort.listen((message) {
    if (message is List) {
      String action = message[0];
      if (action == 'update') {
        updateController.add('update');
      }
    }
  });
  sPort.send(["init", rPort.sendPort]);

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

  final db = await args.dbRef.openRawDatabase();
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
    SqliteConnectionImpl asyncdb, Mutex mutex, Schema schema) async {
  return await asyncdb.inIsolateWriteTransaction((db) async {
    List<String> ops = updateSchema(db, schema);
    return ops;
  });
}
