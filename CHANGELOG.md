## 0.3.0-preview.4

The low-level SQLite-related code is extracted into a separate [sqlite_async](https://pub.dev/packages/sqlite_async) package.
`sqlite_async` handles the the database connection, connection pooling, Isolate management, queries,
transactions, default options, watching, and migrations.

The `powersync` package now just adds automatic sync and dynamic schema management on top. This makes it easy to switch between
using PowerSync, or just using a local database directly.

Breaking changes:
 - `TableUpdate` renamed to `UpdateNotification`.
 - `PowerSyncDatabase.connectionFactory()` renamed to `PowerSyncDatabase.isolateConnectionFactory()`,
   and should only be used to pass the connection to a different isolate.
 - All tables apart from `ps_crud` are dropped and re-created when upgrading to this version.
   This will not result in any data loss, but a full re-sync is required.

Fixes:
 - Fix queries not watching the correct tables in some cases.
 - Fix performance issues on bulk insert/update/delete.

Other changes:
 - Views and triggers are now persisted in the database, instead of using temporary views.
    - This allows reading the views using other tools.
    - It is still not possible to update the views using other tools, since triggers use the custom `powersync_diff` function to compute changes.

## 0.2.0-preview.3

- Use new write checkpoint API for reduced latency on data upload.
- Improve consistency when custom primary keys are used.
- Fix error on `getOptional()`.
- Use `gen_random_uuid()` as an alias for `uuid()` (custom function for SQLite).

## 0.2.0-preview.2

- Performance improvements in downloading changes.

## 0.2.0-preview.1

Breaking change:
- Rename internal tables to all start with `ps_`. All existing local data is deleted and re-synced.

Other changes:
- Add support for local indexes.
- Add support for local-only tables - no changes recorded, and not synced with the remote service.
- Add support for insert-only tables - records changes, but does not persist data or download from the remote service.
- Add `executeBatch()` API: execute the same statement with multiple parameter sets.
- Add `computeWithDatabase()` API: execute a function in the database isolate, with low-level synchronous database access.
- Add `onChange()` call to receive notifications of changes to a set of tables.
- Improve `watch()` to only listen for updates to relevant tables.
- Faster `uuid()` implementation.

## 0.1.1-preview.2

- Require Flutter SDK.

## 0.1.1-preview.1

- First public version.
