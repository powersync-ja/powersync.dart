import 'package:flutter/foundation.dart';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'package:powersync/sqlite_async.dart';

final migrations = SqliteMigrations()
  ..add(SqliteMigration(1, (tx) async {
    await tx.execute(
        'CREATE TABLE local_system(id INTEGER PRIMARY KEY, sync_enabled INTEGER)');
  }));

late final SqliteDatabase sqliteDb;

/// Using a local database to determine which schema to use in the PowerSync database
/// Any other form of local storage could work here.
openSyncModeDatabase() async {
  const dbFilename = 'system.db';
  var path = '';
  // getApplicationSupportDirectory is not supported on Web
  if (kIsWeb) {
    path = dbFilename;
  } else {
    final dir = await getApplicationSupportDirectory();
    path = join(dir.path, dbFilename);
  }

  sqliteDb = SqliteDatabase(path: path);
  await migrations.migrate(sqliteDb);
}

Future<bool> getSyncMode() async {
  var rows = await sqliteDb
      .getAll('SELECT sync_enabled from local_system where id = 1');

  if (rows.isEmpty) {
    await setSyncMode(false);
    return false;
  }

  return rows[0]['sync_enabled'] == 'TRUE';
}

setSyncMode(bool enabled) async {
  var enabledString = enabled ? "TRUE" : "FALSE";
  await sqliteDb.execute(
      'INSERT OR REPLACE INTO local_system(id, sync_enabled) VALUES (1, ?);',
      [enabledString]);
}
