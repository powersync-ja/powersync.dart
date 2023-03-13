import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:powersync/src/db_migration.dart';
import 'package:powersync/src/uuid.dart';

import './mutex.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;

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
      // Postgres compatibility
      functionName: 'uuid_generate_v4',
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
      await migrations.migrate(db);
    });
  }
}

final DatabaseMigrations migrations = DatabaseMigrations()
  ..add(Migration(1, (db) {
    db.execute('''
      DROP TABLE IF EXISTS crud;
      DROP TABLE IF EXISTS oplog;
      DROP TABLE IF EXISTS buckets;
      DROP TABLE IF EXISTS objects_untyped;
    ''');

    final existingTableRows = db.select(
        "SELECT name FROM sqlite_master WHERE type='table' AND name GLOB 'objects__*'");

    for (var row in existingTableRows) {
      db.execute('DROP TABLE ${row['name']}');
    }

    db.execute('''
    CREATE TABLE ps_oplog(
      bucket TEXT NOT NULL,
      op_id INTEGER NOT NULL,
      op INTEGER NOT NULL,
      row_type TEXT,
      row_id TEXT,
      data TEXT,
      hash INTEGER NOT NULL,
      superseded INTEGER NOT NULL);
      
    CREATE INDEX ps_oplog_by_row ON ps_oplog (row_type, row_id) WHERE superseded = 0;
    CREATE INDEX ps_oplog_by_opid ON ps_oplog (bucket, op_id);
    
    CREATE TABLE ps_buckets(
      name TEXT PRIMARY KEY,
      last_applied_op INTEGER NOT NULL DEFAULT 0,
      last_op INTEGER NOT NULL DEFAULT 0,
      target_op INTEGER NOT NULL DEFAULT 0,
      add_checksum INTEGER NOT NULL DEFAULT 0,
      pending_delete INTEGER NOT NULL DEFAULT 0
    );
    
    CREATE TABLE ps_untyped(type TEXT NOT NULL, id TEXT NOT NULL, data TEXT, PRIMARY KEY (type, id));
    
    CREATE TABLE ps_crud (id INTEGER PRIMARY KEY AUTOINCREMENT, data TEXT);
  ''');
  }))
  ..add(Migration(2, (db) {
    db.execute("ALTER TABLE ps_oplog ADD column key TEXT");

    // The existing keys aren't valid anymore.
    // Invalidate checksum for any existing buckets.
    // This will trigger a complete re-sync, while remaining fully consistent.
    db.execute("UPDATE ps_oplog SET hash = 0");

    // Used to supersede old entries per bucket
    db.execute(
        'CREATE INDEX ps_oplog_by_key ON ps_oplog (bucket, key) WHERE superseded = 0');
  }));
