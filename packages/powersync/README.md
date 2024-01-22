# PowerSync SDK for Dart/Flutter

[PowerSync](https://powersync.co) is a service and set of SDKs that keeps PostgreSQL databases in sync with on-device SQLite databases.

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

// Setup connector to backend if you want to sync data.
class BackendConnector extends PowerSyncBackendConnector {
  PowerSyncDatabase db;

  BackendConnector(this.db);
  @override
  Future<PowerSyncCredentials?> fetchCredentials() async {
    // implement fetchCredentials
  }
  @override
  Future<void> uploadData(PowerSyncDatabase database) async {
    // implement uploadData
  }
}

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


  // Connect to backend
  db.connect(connector: BackendConnector(db));
}
```
