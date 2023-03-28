import 'package:sqlite_async/sqlite_async.dart';

final migrations = SqliteMigrations(migrationTable: 'ps_migration')
  ..add(SqliteMigration(1, (tx) async {
    await tx.computeWithDatabase((db) async {
      db.execute('''
      DROP TABLE IF EXISTS crud;
      DROP TABLE IF EXISTS oplog;
      DROP TABLE IF EXISTS buckets;
      DROP TABLE IF EXISTS objects_untyped;
      DROP TABLE IF EXISTS ps_oplog;
      DROP TABLE IF EXISTS ps_buckets;
      DROP TABLE IF EXISTS ps_untyped;
      DROP TABLE IF EXISTS ps_migrations;
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
      key TEXT,
      data TEXT,
      hash INTEGER NOT NULL,
      superseded INTEGER NOT NULL);
      
    CREATE INDEX ps_oplog_by_row ON ps_oplog (row_type, row_id) WHERE superseded = 0;
    CREATE INDEX ps_oplog_by_opid ON ps_oplog (bucket, op_id);
    CREATE INDEX ps_oplog_by_key ON ps_oplog (bucket, key) WHERE superseded = 0;
    
    CREATE TABLE ps_buckets(
      name TEXT PRIMARY KEY,
      last_applied_op INTEGER NOT NULL DEFAULT 0,
      last_op INTEGER NOT NULL DEFAULT 0,
      target_op INTEGER NOT NULL DEFAULT 0,
      add_checksum INTEGER NOT NULL DEFAULT 0,
      pending_delete INTEGER NOT NULL DEFAULT 0
    );
    
    CREATE TABLE ps_untyped(type TEXT NOT NULL, id TEXT NOT NULL, data TEXT, PRIMARY KEY (type, id));
    
    CREATE TABLE IF NOT EXISTS ps_crud (id INTEGER PRIMARY KEY AUTOINCREMENT, data TEXT);
  ''');
    });
  }));
