import 'dart:convert';

import 'package:sqlite_async/sqlite_async.dart';
import 'package:sqlite_async/sqlite3_common.dart';

import 'schema.dart';

/// Sync the schema to the local database.
void updateSchema(CommonDatabase db, Schema schema) {
  db.execute('SELECT powersync_replace_schema(?)', [jsonEncode(schema)]);
}

Future<void> updateSchemaInIsolate(
    SqliteConnection database, Schema schema) async {
  await database.computeWithDatabase((db) async {
    updateSchema(db, schema);
  });
}
