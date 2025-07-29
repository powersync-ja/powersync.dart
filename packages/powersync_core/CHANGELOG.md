## 1.5.0

 - Update the PowerSync core extension to `0.4.2`.
 - Add support for [raw tables](https://docs.powersync.com/usage/use-case-examples/raw-tables), which are user-managed
   regular SQLite tables instead of the JSON-based views managed by PowerSync.

## 1.4.1

 - Rust client: Fix uploading local writes after reconnect.
 - `PowerSyncDatabase.withDatabase`: Rename `loggers` parameter to `logger` for consistency.
 - Fix parsing HTTP errors for sync service unavailability.

## 1.4.0

Add a new sync client implementation written in Rust instead of Dart. While
this client is still experimental, we intend to make it the default in the 
future. The main benefit of this client is faster sync performance, but 
upcoming features will also require this client.
We encourage interested users to try it out by passing `SyncOptions` to the
`connect` method:

```dart
database.connect(
  connector: YourConnector(),
  options: const SyncOptions(
    syncImplementation: SyncClientImplementation.rust,
  ),
);
```

Switching between the clients can be done at any time without compatibility
issues. If you run into issues with the new client, please reach out to us!

## 1.3.1

- Use `package:http` instead of `package:fetch_client` on the web (since the former now uses fetch as well).
- Allow disconnecting in the credentials callback of a connector.
- Deprecate retry and CRUD upload durations as fields and independent parameters. Use the new `SyncOptions` class instead.
- Fix sync progress report after a compaction or defragmentation on the sync service.

## 1.3.0

* Report real-time progress information about downloads through `SyncStatus.downloadProgress`.
* Add `trackPreviousValues` option on `Table` which sets `CrudEntry.previousValues` to previous values on updates.
* Add `trackMetadata` option on `Table` which adds a `_metadata` column that can be used for updates.
  The configured metadata is available through `CrudEntry.metadata`.
* Add `ignoreEmptyUpdates` option which skips creating CRUD entries for updates that don't change any values.

## 1.2.4

 - Fix deadlock when `connect()` is called immediately after opening a database.

## 1.2.3

 - Introduce locks to avoid duplicate sync streams when multiple instances of the same database are opened.
 - Refactor connect / disconnect internally.
 - Warn when multiple instances of the same database are opened.
 - Fix race condition causing data not to be applied while an upload is in progress.
 - Web: Fix token invalidation logic when a sync worker is used.

## 1.2.2

 - Fix handling token invalidation on the web.

## 1.2.1

 - Raise minimum version of core extension to 0.3.11.

## 1.2.0

 - Support bucket priorities and partial syncs.

## 1.1.3

 - Add explicit casts in sync service, avoiding possible issues with dart2js optimizations.

## 1.1.2

 - Web: Support running in contexts where web workers are unavailable.
 - Web: Fix sync worker logs not being disabled.
 - `powersync_sqlcipher`: Web support.

## 1.1.1

- Fix `statusStream` emitting the same sync status multiple times.

## 1.1.0

 - Increase limit on number of columns per table to 1999.
 - Avoid deleting the $local bucket on connect().

## 1.0.0

 - Dart library for Powersync for use cases such as server-side Dart or non-Flutter Dart environments initial release.
