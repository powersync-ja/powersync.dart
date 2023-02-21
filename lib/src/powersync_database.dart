import 'dart:async';
import 'dart:convert';
import 'dart:isolate';

import './background_database.dart';
import './bucket_storage.dart';
import './database_init.dart';
import './isolate_completer.dart';
import './mutex.dart';
import './schema.dart';
import './schema_logic.dart';
import './streaming_sync.dart';
import './thottle.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;

abstract class PowerSyncBackendConnector {
  /// Get credentials for PowerSync.
  /// Return null if no credentials are available.
  Future<String?> getCredentials();

  Future<void> uploadData(PowerSyncDatabase database);
}

/// Use to define custom setup for each SQLite connection
class SqliteConnectionSetup {
  final FutureOr<void> Function() _setup;

  const SqliteConnectionSetup(FutureOr<void> Function() setup) : _setup = setup;

  Future<void> setup() async {
    await _setup();
  }
}

/// Construct on the main thread.
class PowerSyncDatabase {
  final Schema schema;
  final Mutex mutex = Mutex.shared();

  late final Stream<TableUpdate> updates;
  final StreamController<TableUpdate> _updatesController =
      StreamController.broadcast();
  final String path;
  final ReceivePort _eventsPort = ReceivePort();
  SyncStatus _status = const SyncStatus(connected: false, lastSyncedAt: null);
  final StreamController<SyncStatus> _statusStreamController =
      StreamController<SyncStatus>.broadcast();
  late final Stream<SyncStatus> statusStream;
  late final SqliteConnection _internalConnection;
  late final Future<void> _initialized;
  late List<String> _initializeStatements;
  SqliteConnectionSetup? sqliteSetup;

  SendPort? _streamingSyncPort;

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

  /// While initializing is automatic, it is good practice to await on this,
  /// to detect potential initialization errors.
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
        if (action == "getToken") {
          await (data[1] as PortCompleter).handle(() async {
            final token = await connector.getCredentials();
            return token;
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

  SqliteConnection openConnection({String? debugName}) {
    return SqliteConnection(_dbref(), updates: updates, debugName: debugName);
  }

  SqliteConnection _openPrimaryConnection({String? debugName}) {
    return SqliteConnection(_dbref(primary: true),
        updates: updates, debugName: debugName);
  }

  SqliteConnectionFactory _dbref({bool primary = false}) {
    return SqliteConnectionFactory(
        path: path,
        port: _eventsPort.sendPort,
        mutex: mutex,
        primary: primary,
        setup: sqliteSetup);
  }

  bool get connected {
    return _status.connected;
  }

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

class SqliteConnectionFactory {
  String path;
  SendPort port;
  Mutex mutex;
  bool primary;
  SqliteConnectionSetup? setup;

  SqliteConnectionFactory(
      {required this.path,
      required this.port,
      required this.mutex,
      this.setup,
      this.primary = false});

  Future<sqlite.Database> open() async {
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
  String name;

  TableUpdate(this.name);

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
  put('PUT'),
  patch('PATCH'),
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

  Future<String?> loadCredentials() async {
    final r = IsolateResult<String?>();
    sPort.send(["getToken", r.completer]);
    return r.future;
  }

  Future<void> uploadCrud() async {
    final r = IsolateResult<void>();
    sPort.send(["uploadCrud", r.completer]);
    return r.future;
  }

  final db = await args.dbRef.open();
  final storage = BucketStorage(db, mutex: args.mutex);
  final sync = StreamingSyncImplementation(
      adapter: storage,
      credentialsCallback: loadCredentials,
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
  return await asyncdb.inIsolateWriteTransaction((db) async {
    List<String> ops = updateSchema(db, schema);
    return ops;
  });
}
