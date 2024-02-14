# PowerSync SDK for Dart/Flutter

[PowerSync](https://powersync.co) is a service and set of SDKs that keeps PostgreSQL databases in sync with on-device SQLite databases.

## SDK Features

- Real-time streaming of changes.
- Direct access to the SQLite database - use SQL on the client and server.
- Operations are asynchronous by default - does not block the UI.
- Supports one write and many reads concurrently.
- No need for client-side database migrations - these are handled automatically.
- Subscribe to queries for live updates.

## Getting started

```dart
import 'package:powersync/powersync.dart';
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

## Web support

Web support is currently in an alpha release.

### Setup

Web support requires `sqlite3.wasm` and `powersync_db.worker.js` assets to be served from the web application. This is typically achieved by placing the files in the project `web` directory.

These assets are automatically configured in this monorepo when running `melos prepare`.

- `sqlite3.wasm` can be found [here](https://github.com/simolus3/sqlite3.dart/releases)
- `powersync_db.worker.js` will eventually be released in the repo's releases.
  - In the interim the asset can be retrieved from the `./assets` folder after executing `melos prepare`

Currently the Drift SQLite library is used under the hood for DB connections. See [here](https://drift.simonbinder.eu/web/#getting-started) for detailed compatibility
and setup notes.

The same code is used for initializing native and web `PowerSyncDatabase` clients.

### Limitations

The API for web is essentially the same as for native platforms. Some features within `PowerSyncDatabase` clients are not available.

#### Imports

Flutter Web does not support importing directly from `sqlite3.dart` as it uses `dart:ffi`.

Change imports from

```Dart
import 'package/powersync/sqlite3.dart`
```

to

```Dart
import 'package/powersync/sqlite3_common.dart'
```

In code which needs to run on the Web platform. Isolated native specific code can still import from `sqlite3.dart`.

#### Database connections

Web DB connections do not support concurrency. A single DB connection is used. `readLock` and `writeLock` contexts do not
implement checks for preventing writable queries in read connections and vice-versa.

Direct access to the synchronous `CommonDatabase` (`sqlite.Database` equivalent for web) connection is not available. `computeWithDatabase` is not available on web.

Multiple tab support is not yet available. Using multiple tabs will break.
