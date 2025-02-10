import 'package:flutter/foundation.dart';
import 'package:powersync_sqlcipher/powersync.dart';
import 'package:path_provider/path_provider.dart';
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

Future<void> openDatabase() async {
  var path = 'powersync-demo.db';
  // getApplicationSupportDirectory is not supported on Web
  if (!kIsWeb) {
    final dir = await getApplicationSupportDirectory();
    path = join(dir.path, 'powersync-dart.db');
  }

  // Setup the database.
  final cipherFactory = PowerSyncSQLCipherOpenFactory(
      path: path, key: "sqlcipher-encryption-key");

  db = PowerSyncDatabase.withFactory(cipherFactory, schema: schema);

  await db.initialize();

  // Run local statements.
  await db.execute(
      'INSERT INTO customers(id, name, email) VALUES(uuid(), ?, ?)',
      ['Fred', 'fred@example.org']);

  // Connect to backend
  db.connect(connector: BackendConnector(db));
}
