import 'dart:async';

import 'package:powersync/src/database_utils.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;

typedef MigrationFunction = FutureOr<void> Function(sqlite.Database db);

class Migration {
  final MigrationFunction fn;
  final int version;

  const Migration(this.version, this.fn);
}

class DatabaseMigrations {
  List<Migration> migrations = [];

  add(Migration migration) {
    assert(migrations.isEmpty || migrations.last.version < migration.version);

    migrations.add(migration);
  }

  get version {
    return migrations.last.version;
  }

  Future<void> migrate(sqlite.Database db) async {
    await asyncDirectTransaction(db, (db) async {
      db.execute(
          'CREATE TABLE IF NOT EXISTS ps_migrations(id TEXT PRIMARY KEY, version INTEGER)');

      final currentVersionRows =
          db.select('SELECT version FROM ps_migrations WHERE id = ?', ['db']);
      int currentVersion =
          currentVersionRows.isEmpty ? 0 : currentVersionRows.first['version'];
      for (var migration in migrations) {
        if (migration.version > currentVersion) {
          await migration.fn(db);
        }
      }
      db.execute(
          'INSERT OR REPLACE INTO ps_migrations(id, version) VALUES(?, ?)',
          ['db', version]);
    });
  }
}
