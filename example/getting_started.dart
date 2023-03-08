import 'package:powersync/powersync.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart';

const schema = Schema([
  Table('customers', [Column.text('name'), Column.text('email')])
]);

late PowerSyncDatabase db;

openDatabase() async {
  final dir = await getApplicationSupportDirectory();
  final path = join(dir.path, 'powersync-dart.db');
  // Setup the database.
  db = PowerSyncDatabase(schema: schema, path: path);
  await db.initialize();

  // Run local statements.
  await db.execute(
      'INSERT INTO customers(id, name, email) VALUES(uuid(), ?, ?)',
      ['Fred', 'fred@example.org']);
}

connectPowerSync() async {
  // DevConnector stores credentials in-memory by default.
  // Extend the class to persist credentials.
  final connector = DevConnector();

  // Login in dev mode.
  await connector.devLogin(
      endpoint: 'https://myinstance.powersync.co',
      user: 'demo',
      password: 'demo');

  // Connect to PowerSync cloud service and start sync.
  db.connect(connector: connector);
}
