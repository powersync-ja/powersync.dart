import 'dart:convert';

import 'package:sqlite_async/sqlite3_common.dart';
import 'package:sqlite_async/sqlite_async.dart';

import 'schema.dart';

const String maxOpId = '9223372036854775807';

final invalidSqliteCharacters = RegExp(r'''["'%,\.#\s\[\]]''');

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

String? friendlyTableName(String table) {
  final re = RegExp(r"^ps_data__(.+)$");
  final re2 = RegExp(r"^ps_data_local__(.+)$");
  final match = re.firstMatch(table) ?? re2.firstMatch(table);
  return match?.group(1);
}
