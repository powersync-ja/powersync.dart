import 'package:powersync/powersync.dart';

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

  // On native Flutter apps, use something like this to store databases in an
  // appropriate directory:
  // if (!kIsWeb) {
  //   final dir = await getApplicationSupportDirectory();
  //   path = join(dir.path, 'powersync-dart.db');
  // }

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
