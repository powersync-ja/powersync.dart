import 'dart:convert';

import 'package:sqlite_async/sqlite3_common.dart';
import 'package:sqlite_async/sqlite_async.dart';

import 'schema.dart';

const String maxOpId = '9223372036854775807';

final invalidSqliteCharacters = RegExp(r'''["'%,\.#\s\[\]]''');

/// Sync the schema to the local database.
Future<void> updateSchema(SqliteWriteContext tx, Schema schema) async {
  await tx.execute('SELECT powersync_replace_schema(?)', [jsonEncode(schema)]);
}

Future<void> updateSchemaInIsolate(
    SqliteConnection database, Schema schema) async {
  await database.writeTransaction((tx) async {
    await updateSchema(tx, schema);
  });
}

String? friendlyTableName(String table) {
  final re = RegExp(r"^ps_data__(.+)$");
  final re2 = RegExp(r"^ps_data_local__(.+)$");
  final match = re.firstMatch(table) ?? re2.firstMatch(table);
  return match?.group(1);
}
