## 1.3.1

 - http, creds, params

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
