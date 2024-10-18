import 'dart:io';

import 'package:powersync_core/powersync_core.dart';
import 'package:path/path.dart';

const schema = Schema([
  Table('customers', [Column.text('name'), Column.text('email')])
]);

late PowerSyncDatabase db;

// Setup connector to backend if you would like to sync data.
class BackendConnector extends PowerSyncBackendConnector {
  PowerSyncDatabase db;

  BackendConnector(this.db);
  @override
  // ignore: body_might_complete_normally_nullable
  Future<PowerSyncCredentials?> fetchCredentials() async {
    // implement fetchCredentials
  }
  @override
  Future<void> uploadData(PowerSyncDatabase database) async {
    // implement uploadData
  }
}

openDatabase() async {
  const dbFilename = 'powersync-demo.db';
  final dir = (Directory.current.uri).toFilePath();
  var path = join(dir, dbFilename);

  // Setup the database.
  db = PowerSyncDatabase(schema: schema, path: path);
  await db.initialize();

  // Run local statements.
  await db.execute(
      'INSERT INTO customers(id, name, email) VALUES(uuid(), ?, ?)',
      ['Fred', 'fred@example.org']);

  // Connect to backend
  db.connect(connector: BackendConnector(db));
}
