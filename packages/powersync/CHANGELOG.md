## 1.5.5

- Fix issue where `hasSynced` is cleared when offline.

## 1.5.4

- Fix watch query parameter `triggerOnTables` to prepend powersync view names.
- Upgrade dependency `sqlite_async` to version 0.8.1.

## 1.5.3

- Added support for client parameters when connecting.

## 1.5.2

- Refactor `waitForFirstSync()` to iterate through the stream and remove the use of a `Future`.
- Fix sync connection not immediately closed when calling `db.disconnect()` (#114).

## 1.5.1

- Adds a hasSynced flag to check if initial data has been synced.
- Adds a waitForFirstSync method to check if the first full sync has completed.

## 1.5.0

- Upgrade minimum Dart SDK constraint to `3.4.0`.
- Upgrade `sqlite_async` to version 0.7.0 which updates all Database types to use a `CommonDatabase` interface.

## 1.4.2

- Fix `Bad state: Future already completed` error when calling `disconnectAndClear()`.

## 1.4.1

- Upgrades dependency `powersync_flutter_libs` to version `0.1.0`.

## 1.4.0

- Introduces the use of the `powersync-sqlite-core` native extension. This is our common Rust core which means all PowerSync SDKs now use the same core logic for PowerSync functionality, improving maintainability and support.
- Added a new package dependency on `powersync_flutter_libs` for loading the extension.

## 1.3.0-alpha.10

- Added support for client parameters when connecting.
- Fix watch query parameter `triggerOnTables` to prepend powersync view names.
- Upgrade dependency `sqlite_async` to version 0.8.1.
- Fix issue where `hasSynced` is cleared when offline.

## 1.3.0-alpha.9

- Updated sqlite_async to use Navigator locks for limiting sync stream implementations in multiple tabs

## 1.3.0-alpha.8

- **FIX**(powersync-attachements-helper): pubspec file (#29).
- **DOCS**: update readme and getting started (#51).
- Updates and uses the latest `sqlite_async` package.

## 1.3.0-alpha.7

- Updates and uses the latest `sqlite_async` alpha.

## 1.3.0-alpha.6

- Fix `Bad state: Future already completed` error when calling `disconnectAndClear()`.

## 1.3.1

- Fix "Checksum mismatch" issue when calling `PowerSyncDatabase.connect` multiple times.

## 1.3.0

- Add `crudThrottleTime` option to arguments when running `PowerSyncDatabase.connect` to set throttle time for crud operations.

## 1.3.0-alpha.5

- Update `sqlite_async.dart` dependency
- Fix issue where sync stream connection would fail to connect https://github.com/powersync-ja/powersync.dart/issues/11

## 1.3.0-alpha.4

- Merge master branch in and resolve conflicts

## 1.3.0-alpha.3

- Fixed issue where disconnectAndClear would prevent subsequent sync connection on native platforms and would fail to clear the database on web.

## 1.3.0-alpha.2

- **FIX**(powersync-attachements-helper): pubspec file (#29).
- **DOCS**: update readme and getting started (#51).

## 1.3.0-alpha.1

- Added initial support for Web platform.

## 1.2.2

- Deprecate DevConnector and related

## 1.2.1

- Fix indexes incorrectly dropped after the first run.
- Fix `viewName` override causing `view "..." already exists` errors after the first run.

## 1.2.0

This release improves the default log output and errors to better assist in debugging.

Breaking changes:

- `PowerSyncCredentials` constructor is no longer const, and the `endpoint` URL is validated in the constructor.
- Different error and exception classes are now used by the library, including `CredentialsException`, `SyncResponseException` and `PowerSyncProtocolException`, instead of more generic `AssertionError` and `HttpException`.

Other changes:

- The library now logs to the console in debug builds by default. To get the old behavior, use `logger: attachedLogger` in the `PowerSyncDatabase` constructor.
- Log messages have been improved to better explain the sync process and errors.

## 1.1.1

- Fix error occasionally occurring when calling `powersync.connect()` right when opening the database.
- Update getting started docs.

## 1.1.0

- Fix delete operations rejected by the server not being reverted locally.
- Expand `SyncStatus` to include `connected`, `downloading`, `uploading` status, as well as the last errors.
- Fix `SyncStatus.connected` to be updated when calling `PowerSyncDatabase.disconnect()`.
- Fix network error messages only containing a single character in some cases.
- Update `sqlite_async` dependency:
  - Supports catching errors in transactions and continuing the transaction.
  - Add `tx.closed` and `db/tx.getAutoCommit()`
- Update `uuid` dependency:
  - Now uses `CryptoRNG` from `uuid` package now that the performance improvements are upstream.
- Requires Dart ^3.2.0 / Flutter ^3.16.0.

## 1.0.0

- Start using stable version range.

## 0.4.2

- Improve HTTP error messages.
- Enable SQLite recursive triggers.
- Support overriding view names.
- _Breaking change:_ Validate schema definitions for duplicates.
  Remove `id` column and indexes from any tables in the schema if present.

## 0.4.1

- Use Apache 2.0 license.
- Update uuid dependency.

## 0.4.0

Improvements:

- Some parameters to `PowerSyncCredentials` are now optional.
- Upgrade dependencies.

## 0.4.0-preview.6

New functionality:

- Include transaction ids on crud entries, allowing transactions to be grouped together.
- Simplify implementation of `PowerSyncBackendConnector` by automatically handling token caching.

Fixes:

- Only check token expiration on the server, avoiding issues when the local time is out of sync.
- Fix some edge case errors that would kill the sync Isolate.
- Fix errors when disconnecting shortly after connecting.

Breaking changes:

- `PowerSyncDatabase.disconnect()` now returns `Future<void>` instead of `void`.
- Subclasses of `PowerSyncBackendConnector` must now implement `fetchCredentials()` instead of `refreshCredentials()` + `getCredentials()`.

Other changes:

- Update sqlite_async dependency to 0.4.0: <https://pub.dev/packages/sqlite_async/changelog>

## 0.3.0-preview.5

- Link github repository.

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
