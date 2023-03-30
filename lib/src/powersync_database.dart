import 'dart:async';
import 'dart:isolate';

import 'package:logging/logging.dart';
import 'package:powersync/src/powersync_update_notification.dart';
import 'package:sqlite_async/sqlite3.dart' as sqlite;
import 'package:sqlite_async/sqlite_async.dart';

import 'bucket_storage.dart';
import 'connector.dart';
import 'crud.dart';
import 'isolate_completer.dart';
import 'log.dart';
import 'migrations.dart';
import 'open_factory.dart';
import 'schema.dart';
import 'schema_logic.dart';
import 'streaming_sync.dart';

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
  final Schema schema;

  final SqliteDatabase database;

  /// Current connection status.
  SyncStatus currentStatus =
      const SyncStatus(connected: false, lastSyncedAt: null);

  /// Use this stream to subscribe to connection status updates.
  late final Stream<SyncStatus> statusStream;

  final StreamController<SyncStatus> _statusStreamController =
      StreamController<SyncStatus>.broadcast();

  @override
  late final Stream<UpdateNotification> updates;

  SendPort? _streamingSyncPort;
  late Future<void> _initialized;

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
  factory PowerSyncDatabase(
      {required Schema schema,
      required String path,
      int maxReaders = SqliteDatabase.defaultMaxReaders,
      @Deprecated("Use [PowerSyncDatabase.withFactory] instead")
          // ignore: deprecated_member_use_from_same_package
          SqliteConnectionSetup? sqliteSetup}) {
    // ignore: deprecated_member_use_from_same_package
    var factory = PowerSyncOpenFactory(path: path, sqliteSetup: sqliteSetup);
    return PowerSyncDatabase.withFactory(factory, schema: schema);
  }

  factory PowerSyncDatabase.withFactory(PowerSyncOpenFactory openFactory,
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
    _initialized = _init();
  }

  Future<void> _init() async {
    statusStream = _statusStreamController.stream;
    await database.initialize();
    await migrations.migrate(database);
    await updateSchemaInIsolate(database, schema);
  }

  /// Wait for initialization to complete.
  ///
  /// While initializing is automatic, this helps to catch and report initialization errors.
  Future<void> initialize() {
    return _initialized;
  }

  /// Connect to the PowerSync service, and keep the databases in sync.
  ///
  /// The connection is automatically re-opened if it fails for any reason.
  ///
  /// Status changes are reported on [statusStream].
  connect({required PowerSyncBackendConnector connector}) async {
    await _initialized;
    final dbref = database.isolateConnectionFactory();
    ReceivePort rPort = ReceivePort();
    disconnect();
    StreamSubscription? updateSubscription;
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
          var throttled = UpdateNotification.throttleStream(
              updates, const Duration(milliseconds: 10));
          updateSubscription = throttled.listen((event) {
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
          updateSubscription?.cancel();
        } else if (action == 'log') {
          LogRecord record = data[1];
          log.log(
              record.level, record.message, record.error, record.stackTrace);
        }
      }
    });

    Isolate.spawn(_powerSyncDatabaseIsolate,
        _PowerSyncDatabaseIsolateArgs(rPort.sendPort, dbref),
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

  @override
  Future<void> close() async {
    await database.close();
  }

  /// Takes a read lock, without starting a transaction.
  ///
  /// In most cases, [readTransaction] should be used instead.
  @override
  Future<T> readLock<T>(Future<T> Function(SqliteReadContext tx) callback,
      {Duration? lockTimeout}) async {
    await _initialized;
    return database.readLock(callback);
  }

  /// Takes a global lock, without starting a transaction.
  ///
  /// In most cases, [writeTransaction] should be used instead.
  @override
  Future<T> writeLock<T>(Future<T> Function(SqliteWriteContext tx) callback,
      {Duration? lockTimeout}) async {
    await _initialized;
    return database.writeLock(callback);
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

class _PowerSyncDatabaseIsolateArgs {
  SendPort sPort;
  IsolateConnectionFactory dbRef;

  _PowerSyncDatabaseIsolateArgs(this.sPort, this.dbRef);
}

Future<void> _powerSyncDatabaseIsolate(
    _PowerSyncDatabaseIsolateArgs args) async {
  final sPort = args.sPort;
  ReceivePort rPort = ReceivePort();
  StreamController updateController = StreamController.broadcast();
  final upstreamDbClient = args.dbRef.upstreamPort.open();

  sqlite.Database? db;
  rPort.listen((message) {
    if (message is List) {
      String action = message[0];
      if (action == 'update') {
        updateController.add('update');
      } else if (action == 'close') {
        db?.dispose();
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

  db = await args.dbRef.openFactory
      .open(SqliteOpenOptions(primaryConnection: false, readOnly: false));
  final mutex = args.dbRef.mutex.open();
  final storage = BucketStorage(db, mutex: mutex);
  final sync = StreamingSyncImplementation(
      adapter: storage,
      credentialsCallback: loadCredentials,
      invalidCredentialsCallback: invalidateCredentials,
      uploadCrud: uploadCrud,
      updateStream: updateController.stream);
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

  db.updates.listen((event) {
    updatedTables.add(event.tableName);

    updateDebouncer ??=
        Timer(const Duration(milliseconds: 10), maybeFireUpdates);
  });
}
