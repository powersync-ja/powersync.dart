# PowerSync SDK for Dart/Flutter

[PowerSync](https://powersync.co) is a service and set of SDKs that keeps PostgreSQL databases in sync with on-device SQLite databases.

## SDK Features

* Real-time streaming of changes.
* Direct access to the SQLite database - use SQL on the client and server.
* Operations are asynchronous by default - does not block the UI.
* Supports one write and many reads concurrently.
* No need for client-side database migrations - these are handled automatically.
* Subscribe to queries for live updates.

## Examples

For complete app examples, see our [example app gallery](https://docs.powersync.com/resources/demo-apps-example-projects#flutter)

For examples of some common patterns, see our [example snippets](./example/README.md)

## Getting started

You'll need to create a PowerSync account and set up a PowerSync instance. You can do this at [https://www.powersync.com/](https://www.powersync.com/).

### Install the package

`flutter pub add powersync`

### Implement a backend connector and initialize the Powersync database

```dart
import 'package:powersync/powersync.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart';

// Define the schema for the local SQLite database.
// You can automatically generate this schema based on your sync rules:
// In the Powersync dashboard, right-click on your PowerSync instance and then click "Generate client-side schema"
const schema = Schema([
  Table('customers', [Column.text('name'), Column.text('email')])
]);

late PowerSyncDatabase db;

// You must implement a backend connector to define how Powersync communicates with your backend.
class MyBackendConnector extends PowerSyncBackendConnector {
  PowerSyncDatabase db;

  MyBackendConnector(this.db);
  @override
  Future<PowerSyncCredentials?> fetchCredentials() async {
    // implement fetchCredentials to obtain a JWT from your authentication service
    // see https://docs.powersync.com/usage/installation/authentication-setup
  }
  @override
  Future<void> uploadData(PowerSyncDatabase database) async {
    // Implement uploadData to send local changes to your backend service
    // You can omit this method if you only want to sync data from the server to the client
    // see https://docs.powersync.com/usage/installation/upload-data
  }
}

openDatabase() async {
  final dir = await getApplicationSupportDirectory();
  final path = join(dir.path, 'powersync-dart.db');

  // Setup the database.
  db = PowerSyncDatabase(schema: schema, path: path);
  await db.initialize();

  // Connect to backend
  db.connect(connector: MyBackendConnector(db));
}
```

### Subscribe to changes in data

```dart
StreamBuilder(
  // you can watch any SQL query
  stream: return db.watch('SELECT * FROM customers order by id asc'),
  builder: (context, snapshot) {
    if (snapshot.hasData) {
      // TODO: implement your own UI here based on the result set
      return ...;
    } else {
      return const Center(child: CircularProgressIndicator());
    }
  },
)
```

### Insert, update, and delete data in the SQLite database as you would normally

```dart
FloatingActionButton(
  onPressed: () async {
    await db.execute(
      'INSERT INTO customers(id, name, email) VALUES(uuid(), ?, ?)',
      ['Fred', 'fred@example.org'],
    );
  },
  tooltip: '+',
  child: const Icon(Icons.add),
);
```

### Send changes in local data to your backend service

```dart
// Implement the uploadData method in your backend connector
@override
Future<void> uploadData(PowerSyncDatabase database) async {
  final batch = await database.getCrudBatch();
  if (batch == null) return;
  for (var op in batch.crud) {
    switch (op.op) {
      case UpdateType.put:
        // Send the data to your backend service
        // replace `_myApi` with your own API client or service
        await _myApi.put(op.table, op.opData!);
        break;
      default:
        // TODO: implement the other operations (patch, delete)
        break;
    }
  }
  await batch.complete();
}
```

### Logging

You can enable logging to see what's happening under the hood
or to debug connection/authentication/sync issues.

```dart
Logger.root.level = Level.INFO;
Logger.root.onRecord.listen((record) {
  if (kDebugMode) {
    print('[${record.loggerName}] ${record.level.name}: ${record.time}: ${record.message}');

    if (record.error != null) {
      print(record.error);
    }
    if (record.stackTrace != null) {
      print(record.stackTrace);
    }
  }
});
```

