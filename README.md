PowerSync makes it easy to keep a local SQLite database in sync with backend SQL databases.

## Features

 * Direct access to the SQLite database - use SQL on the client and server.
 * Operations are asynchronous by default, avoiding blocking the UI.
 * Supports one write and many reads concurrently.
 * Client-side migrations are handled automatically.

## Getting started

Import PowerSync

```dart
import 'package:powersync/powersync.dart';

// To get a database path on Flutter
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart';

const schema = Schema([
  Table('customers', [Column.text('name'), Column.text('email')])
]);


late PowerSyncDatabase db;

Future<void> openDatabase() {
  final dir = await getApplicationSupportDirectory();
  final path = join(dir.path, 'powersync-dart.db');
  // Setup the database
  db = PowerSyncDatabase(schema: schema, path: await getDatabasePath());
  await db.initialize();

  // Run local statements
  await db.execute('INSERT INTO customers(id, name, email) VALUES(uuid(), ?, ?)', ['Fred', 'fred@example.org']);

  // Connect to PowerSync cloud service and start sync
  db.connect(
      connector:
          const DevConnector(credentialsCallback: loadPowerSyncCredentials));
}


Future<String> loadPowerSyncCredentials() {
  return Future.value(
      """{"token":"my_token","endpoint":"https://myinstance.powersync.co"}""");
}


```
