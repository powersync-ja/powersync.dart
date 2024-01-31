import 'package:powersync/sqlite_async.dart';

import 'schema.dart';
import 'schema_helpers.dart';

Future<void> updateSchemaInIsolate(
    SqliteConnection database, Schema schema) async {
  await database.writeLock((tx) async {
    await updateSchema(tx, schema);
  });
}
