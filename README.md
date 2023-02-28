# PowerSync SDK for Dart/Flutter

[PowerSync](https://powersync.co) is a cloud service and Flutter SDK that keeps PostgreSQL databases in sync with on-device SQLite databases.

## SDK Features

 * Real-time streaming of changes.
 * Direct access to the SQLite database - use SQL on the client and server.
 * Operations are asynchronous by default - does not block the UI.
 * Supports one write and many reads concurrently.
 * No need for client-side database migrations - these are handled automatically.
 * Subscribe to queries for live updates.

## Getting started


```dart
import 'package:powersync/powersync.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart';

const schema = Schema([
  Table('customers', [Column.text('name'), Column.text('email')])
]);


late PowerSyncDatabase db;

Future<void> openDatabase() {
  final dir = await getApplicationSupportDirectory();
  final path = join(dir.path, 'powersync-dart.db');
  // Setup the database.
  db = PowerSyncDatabase(schema: schema, path: await getDatabasePath());
  await db.initialize();

  // Run local statements.
  await db.execute('INSERT INTO customers(id, name, email) VALUES(uuid(), ?, ?)', ['Fred', 'fred@example.org']);
}

Future<void> connectPowerSync() {
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
```
