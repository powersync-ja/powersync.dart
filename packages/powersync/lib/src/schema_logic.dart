import 'dart:convert';

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
  const prefix1 = 'ps_data__';
  const prefix2 = 'ps_data_local__';

  if (table.startsWith(prefix2)) {
    return table.substring(prefix2.length);
  } else if (table.startsWith(prefix1)) {
    return table.substring(prefix1.length);
  } else {
    return null;
  }
}
