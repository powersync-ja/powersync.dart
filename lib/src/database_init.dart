import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:math';
import 'dart:typed_data';

import './mutex.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;
import 'package:uuid/uuid.dart';

final _secureRandom = Random.secure();

// Around 2x faster than the implementation from package:uuid/uuid_util.dart
Uint8List cryptoRNG() {
  final b = Uint8List(16);

  for (var i = 0; i < 16; i += 4) {
    var k = _secureRandom.nextInt(1 << 32);
    b[i] = k;
    b[i + 1] = k >> 8;
    b[i + 2] = k >> 16;
    b[i + 3] = k >> 24;
  }

  return b;
}

const uuid = Uuid(options: {'grng': cryptoRNG});
// const uuid = Uuid();

class DatabaseInit {
  late final sqlite.Database db;
  final String path;

  DatabaseInit(this.path);

  Future<sqlite.Database> open(
      {sqlite.OpenMode mode = sqlite.OpenMode.readWriteCreate}) async {
    db = sqlite.sqlite3.open(path, mode: mode, mutex: false);
    await _init();
    return db;
  }

  Future<void> _init() async {
    _setupFunctions();
    _setupParams();
  }

  void _setupParams() {
    // These must all be connection-scoped, and may not lock the database.

    // Done on the main connection:
    //   db.execute('PRAGMA journal_mode = WAL');
    // Can investigate using no journal for bucket data

    // Default is FULL.
    // NORMAL is faster, and still safe for WAL mode.
    // Can investigate synchronous = OFF for the bucket data
    // > If the application running SQLite crashes, the data will be safe, but the database might become corrupted if the operating system crashes or the computer loses power before that data has been written to the disk surface. On the other hand, commits can be orders of magnitude faster with synchronous OFF.
    db.execute('PRAGMA synchronous = NORMAL');

    // Set journal_size_limit to reclaim WAL space
    db.execute('PRAGMA journal_size_limit = 20000000');

    // This would avoid the need for a shared-memory wal-index.
    // However, it seems like Dart isolates + sqlite3 ffi does use the equivalent
    // of multiple processes, so we can't use this.
    // db.execute('PRAGMA locking_mode = EXCLUSIVE');
  }

  void _setupFunctions() {
    db.createFunction(
      functionName: 'uuid',
      argumentCount: const sqlite.AllowedArgumentCount(0),
      function: (args) => uuid.v4(),
    );

    db.createFunction(
        functionName: 'powersync_diff',
        argumentCount: const sqlite.AllowedArgumentCount(2),
        deterministic: true,
        directOnly: false,
        function: (args) {
          final oldData = jsonDecode(args[0] as String) as Map<String, dynamic>;
          final newData = jsonDecode(args[1] as String) as Map<String, dynamic>;

          Map<String, dynamic> result = {};

          for (final newEntry in newData.entries) {
            final oldValue = oldData[newEntry.key];
            final newValue = newEntry.value;

            if (newValue != oldValue) {
              result[newEntry.key] = newValue;
            }
          }

          for (final key in oldData.keys) {
            if (!newData.containsKey(key)) {
              result[key] = null;
            }
          }

          return jsonEncode(result);
        });

    db.createFunction(
      functionName: 'powersync_sleep',
      argumentCount: const sqlite.AllowedArgumentCount(1),
      function: (args) {
        final millis = args[0] as int;
        sleep(Duration(milliseconds: millis));
        return millis;
      },
    );

    db.createFunction(
      functionName: 'powersync_connection_name',
      argumentCount: const sqlite.AllowedArgumentCount(0),
      function: (args) {
        return Isolate.current.debugName;
      },
    );
  }

  close() {
    db.dispose();
  }
}

class DatabaseInitPrimary extends DatabaseInit {
  final Mutex mutex;

  DatabaseInitPrimary(super.path, {required this.mutex});

  @override
  Future<void> _init() async {
    await mutex.lock(() async {
      db.execute('PRAGMA journal_mode = WAL');
    });
    super._init();

    await _migrate();
  }

  Future<void> _migrate() async {
    await mutex.lock(() async {
      db.execute('''
    CREATE TABLE IF NOT EXISTS ps_oplog(
      bucket TEXT NOT NULL,
      op_id INTEGER NOT NULL,
      op INTEGER NOT NULL,
      object_type TEXT,
      object_id TEXT,
      data TEXT,
      hash INTEGER NOT NULL,
      superseded INTEGER NOT NULL);
      
    CREATE INDEX IF NOT EXISTS ps_oplog_by_object ON ps_oplog (object_type, object_id) WHERE superseded = 0;
    CREATE INDEX IF NOT EXISTS ps_oplog_by_opid ON ps_oplog (bucket, op_id);
    
    CREATE TABLE IF NOT EXISTS ps_buckets(
      name TEXT PRIMARY KEY,
      last_applied_op INTEGER NOT NULL DEFAULT 0,
      last_op INTEGER NOT NULL DEFAULT 0,
      target_op INTEGER NOT NULL DEFAULT 0,
      add_checksum INTEGER NOT NULL DEFAULT 0,
      pending_delete INTEGER NOT NULL DEFAULT 0
    );
    
    CREATE TABLE IF NOT EXISTS ps_untyped(type TEXT NOT NULL, id TEXT NOT NULL, data TEXT, PRIMARY KEY (type, id));
    
    CREATE TABLE IF NOT EXISTS ps_crud (id INTEGER PRIMARY KEY AUTOINCREMENT, data TEXT);
  ''');
    });
  }
}
