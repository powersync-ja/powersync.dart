# Change Log

All notable changes to this project will be documented in this file.
See [Conventional Commits](https://conventionalcommits.org) for commit guidelines.

## 2025-08-11

### Changes

---

Packages with breaking changes:

 - There are no breaking changes in this release.

Packages with other changes:

 - [`powersync_core` - `v1.5.1`](#powersync_core---v151)
 - [`powersync` - `v1.15.1`](#powersync---v1151)
 - [`powersync_sqlcipher` - `v0.1.11`](#powersync_sqlcipher---v0111)
 - [`powersync_flutter_libs` - `v0.4.11`](#powersync_flutter_libs---v0411)

---

#### `powersync_core` - `v1.5.1`
#### `powersync` - `v1.15.1`
#### `powersync_sqlcipher` - `v0.1.11`
#### `powersync_flutter_libs` - `v0.4.11`

 - Support latest versions of `package:sqlite3` and `package:sqlite_async`.
 - Stream client: Improve `disconnect()` while a connection is being opened.
 - Stream client: Support binary sync lines with Rust client and compatible PowerSync service versions.
 - Sync client: Improve parsing error responses.

## 2025-07-17

### Changes

---

Packages with breaking changes:

 - There are no breaking changes in this release.

Packages with other changes:

 - [`powersync_core` - `v1.5.0`](#powersync_core---v150)
 - [`powersync` - `v1.15.0`](#powersync---v1150)
 - [`powersync_sqlcipher` - `v0.1.10`](#powersync_sqlcipher---v0110)
 - [`powersync_flutter_libs` - `v0.4.10`](#powersync_flutter_libs---v0410)
 - [`powersync_attachments_helper` - `v0.6.18+11`](#powersync_attachments_helper---v061811)

Packages with dependency updates only:

> Packages listed below depend on other packages in this workspace that have had changes. Their versions have been incremented to bump the minimum dependency versions of the packages they depend upon in this project.

 - `powersync_attachments_helper` - `v0.6.18+11`

---

#### `powersync_flutter_libs` - `v0.4.10`.

 - Update the PowerSync core extension to `0.4.2`.

#### `powersync_core` - `v1.5.0`
#### `powersync` - `v1.15.0`
#### `powersync_sqlcipher` - `v0.1.10`

 - Add support for [raw tables](https://docs.powersync.com/usage/use-case-examples/raw-tables), which are user-managed
   regular SQLite tables instead of the JSON-based views managed by PowerSync.


## 2025-07-07

### Changes

---

Packages with breaking changes:

 - There are no breaking changes in this release.

Packages with other changes:

 - [`powersync_core` - `v1.4.1`](#powersync_core---v141)
 - [`powersync` - `v1.14.1`](#powersync---v1141)
 - [`powersync_sqlcipher` - `v0.1.9`](#powersync_sqlcipher---v019)
 - [`powersync_attachments_helper` - `v0.6.18+10`](#powersync_attachments_helper---v061810)

Packages with dependency updates only:

> Packages listed below depend on other packages in this workspace that have had changes. Their versions have been incremented to bump the minimum dependency versions of the packages they depend upon in this project.

 - `powersync_attachments_helper` - `v0.6.18+10`

---

#### `powersync_core` - `v1.4.1`
#### `powersync` - `v1.14.1`
#### `powersync_sqlcipher` - `v0.1.9`

 - Rust client: Fix uploading local writes after reconnect.
 - `PowerSyncDatabase.withDatabase`: Rename `loggers` parameter to `logger` for consistency.
 - Fix parsing HTTP errors for sync service unavailability.

## 2025-06-19

### Changes

---

Packages with breaking changes:

 - There are no breaking changes in this release.

Packages with other changes:

 - [`powersync_core` - `v1.4.0`](#powersync_core---v140)
 - [`powersync` - `v1.14.0`](#powersync---v1140)
 - [`powersync_sqlcipher` - `v0.1.8`](#powersync_sqlcipher---v018)
 - [`powersync_attachments_helper` - `v0.6.18+9`](#powersync_attachments_helper---v06189)

Packages with dependency updates only:

> Packages listed below depend on other packages in this workspace that have had changes. Their versions have been incremented to bump the minimum dependency versions of the packages they depend upon in this project.

 - `powersync_attachments_helper` - `v0.6.18+9`

---

#### `powersync_core` - `v1.4.0`

#### `powersync` - `v1.14.0`

#### `powersync_sqlcipher` - `v0.1.8`

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

#### `powersync_flutter_libs` - `v0.4.9`

 - Update PowerSync core extension to version 0.4.0.

## 2025-05-29

### Changes

---

Packages with breaking changes:

 - There are no breaking changes in this release.

Packages with other changes:

 - [`powersync_core` - `v1.3.1`](#powersync_core---v131)
 - [`powersync` - `v1.13.1`](#powersync---v1131)
 - [`powersync_sqlcipher` - `v0.1.7`](#powersync_sqlcipher---v017)
 - [`powersync_attachments_helper` - `v0.6.18+8`](#powersync_attachments_helper---v06188)

Packages with dependency updates only:

> Packages listed below depend on other packages in this workspace that have had changes. Their versions have been incremented to bump the minimum dependency versions of the packages they depend upon in this project.

 - `powersync_attachments_helper` - `v0.6.18+8`

---

#### `powersync_core` - `v1.3.1`

- Use `package:http` instead of `package:fetch_client` on the web (since the former now uses fetch as well).
- Allow disconnecting in the credentials callback of a connector.
- Deprecate retry and CRUD upload durations as fields and independent parameters. Use the new `SyncOptions` class instead.
- Fix sync progress report after a compaction or defragmentation on the sync service.

#### `powersync` - `v1.13.1`

- Use `package:http` instead of `package:fetch_client` on the web (since the former now uses fetch as well).
- Allow disconnecting in the credentials callback of a connector.
- Deprecate retry and CRUD upload durations as fields and independent parameters. Use the new `SyncOptions` class instead.
- Fix sync progress report after a compaction or defragmentation on the sync service.

#### `powersync_sqlcipher` - `v0.1.7`

 - Allow subclassing open factory for SQLCipher.


## 2025-05-07

### Changes

---

Packages with breaking changes:

 - There are no breaking changes in this release.

Packages with other changes:

 - [`powersync_core` - `v1.3.0`](#powersync_core---v130)
 - [`powersync` - `v1.13.0`](#powersync---v1130)
 - [`powersync_sqlcipher` - `v0.1.6`](#powersync_sqlcipher---v016)
 - [`powersync_flutter_libs` - `v0.4.8`](#powersync_flutter_libs---v048)
 - [`powersync_attachments_helper` - `v0.6.18+7`](#powersync_attachments_helper---v06187)

Packages with dependency updates only:

> Packages listed below depend on other packages in this workspace that have had changes. Their versions have been incremented to bump the minimum dependency versions of the packages they depend upon in this project.

 - `powersync_attachments_helper` - `v0.6.18+7`

---

#### `powersync_core` - `v1.3.0`
#### `powersync` - `v1.13.0`
#### `powersync_sqlcipher` - `v0.1.6`

* Report real-time progress information about downloads through `SyncStatus.downloadProgress`.
* Add `trackPreviousValues` option on `Table` which sets `CrudEntry.previousValues` to previous values on updates.
* Add `trackMetadata` option on `Table` which adds a `_metadata` column that can be used for updates.
  The configured metadata is available through `CrudEntry.metadata`.
* Add `ignoreEmptyUpdates` option which skips creating CRUD entries for updates that don't change any values.

#### `powersync_flutter_libs` - `v0.4.8`

 - Update PowerSync core extension to version 0.3.14.


## 2025-04-24

### Changes

---

Packages with breaking changes:

 - There are no breaking changes in this release.

Packages with other changes:

 - [`powersync_core` - `v1.2.4`](#powersync_core---v124)
 - [`powersync_attachments_helper` - `v0.6.18+6`](#powersync_attachments_helper---v06186)
 - [`powersync_sqlcipher` - `v0.1.5+4`](#powersync_sqlcipher---v0154)
 - [`powersync` - `v1.12.4`](#powersync---v1124)

Packages with dependency updates only:

> Packages listed below depend on other packages in this workspace that have had changes. Their versions have been incremented to bump the minimum dependency versions of the packages they depend upon in this project.

 - `powersync_attachments_helper` - `v0.6.18+6`
 - `powersync_sqlcipher` - `v0.1.5+4`
 - `powersync` - `v1.12.4`

---

#### `powersync_core` - `v1.2.4`

 - Fix deadlock when `connect()` is called immediately after opening a database.


## 2025-04-22

### Changes

---

Packages with breaking changes:

 - There are no breaking changes in this release.

Packages with other changes:

 - [`powersync_core` - `v1.2.3`](#powersync_core---v123)
 - [`powersync_attachments_helper` - `v0.6.18+5`](#powersync_attachments_helper---v06185)
 - [`powersync_sqlcipher` - `v0.1.5+3`](#powersync_sqlcipher---v0153)
 - [`powersync` - `v1.12.3`](#powersync---v1123)

Packages with dependency updates only:

> Packages listed below depend on other packages in this workspace that have had changes. Their versions have been incremented to bump the minimum dependency versions of the packages they depend upon in this project.

 - `powersync_attachments_helper` - `v0.6.18+5`
 - `powersync_sqlcipher` - `v0.1.5+3`
 - `powersync` - `v1.12.3`

---

#### `powersync_core` - `v1.2.3`

 - Introduce locks to avoid duplicate sync streams when multiple instances of the same database are opened.
 - Refactor connect / disconnect internally.
 - Warn when multiple instances of the same database are opened.
 - Fix race condition causing data not to be applied while an upload is in progress.
 - Web: Fix token invalidation logic when a sync worker is used.


## 2025-03-11

### Changes

---

Packages with breaking changes:

 - There are no breaking changes in this release.

Packages with other changes:

 - [`powersync_core` - `v1.2.2`](#powersync_core---v122)
 - [`powersync_attachments_helper` - `v0.6.18+4`](#powersync_attachments_helper---v06184)
 - [`powersync_sqlcipher` - `v0.1.5+2`](#powersync_sqlcipher---v0152)
 - [`powersync` - `v1.12.2`](#powersync---v1122)

Packages with dependency updates only:

> Packages listed below depend on other packages in this workspace that have had changes. Their versions have been incremented to bump the minimum dependency versions of the packages they depend upon in this project.

 - `powersync_attachments_helper` - `v0.6.18+4`
 - `powersync_sqlcipher` - `v0.1.5+2`
 - `powersync` - `v1.12.2`

---

#### `powersync_core` - `v1.2.2`

 - Fix handling token invalidation on the web.


## 2025-03-06

### Changes

---

Packages with breaking changes:

 - There are no breaking changes in this release.

Packages with other changes:

 - [`powersync_core` - `v1.2.1`](#powersync_core---v121)
 - [`powersync_flutter_libs` - `v0.4.7`](#powersync_flutter_libs---v047)
 - [`powersync_attachments_helper` - `v0.6.18+3`](#powersync_attachments_helper---v06183)
 - [`powersync_sqlcipher` - `v0.1.5+1`](#powersync_sqlcipher---v0151)
 - [`powersync` - `v1.12.1`](#powersync---v1121)

Packages with dependency updates only:

> Packages listed below depend on other packages in this workspace that have had changes. Their versions have been incremented to bump the minimum dependency versions of the packages they depend upon in this project.

 - `powersync_attachments_helper` - `v0.6.18+3`
 - `powersync_sqlcipher` - `v0.1.5+1`
 - `powersync` - `v1.12.1`

---

#### `powersync_core` - `v1.2.1`

 - Raise minimum version of core extension to 0.3.11.

#### `powersync_flutter_libs` - `v0.4.7`

 - Update core extension to 0.3.12.


## 2025-03-03

### Changes

---

Packages with breaking changes:

 - There are no breaking changes in this release.

Packages with other changes:

 - [`powersync_core` - `v1.2.0`](#powersync_core---v120)
 - [`powersync_flutter_libs` - `v0.4.6`](#powersync_flutter_libs---v046)
 - [`powersync` - `v1.12.0`](#powersync---v1120)
 - [`powersync_sqlcipher` - `v0.1.5`](#powersync_sqlcipher---v015)
 - [`powersync_attachments_helper` - `v0.6.18+2`](#powersync_attachments_helper---v06182)

Packages with dependency updates only:

> Packages listed below depend on other packages in this workspace that have had changes. Their versions have been incremented to bump the minimum dependency versions of the packages they depend upon in this project.

 - `powersync_attachments_helper` - `v0.6.18+2`

---

#### `powersync_core` - `v1.2.0`

 - Support bucket priorities and partial syncs.

#### `powersync_flutter_libs` - `v0.4.6`

 - Bump version of core extension to 0.3.11

#### `powersync` - `v1.12.0`

 - Support bucket priorities and partial syncs.

#### `powersync_sqlcipher` - `v0.1.5`

 - Support bucket priorities and partial syncs.


## 2025-02-17

### Changes

---

Packages with breaking changes:

 - There are no breaking changes in this release.

Packages with other changes:

 - [`powersync_core` - `v1.1.3`](#powersync_core---v113)
 - [`powersync_flutter_libs` - `v0.4.5`](#powersync_flutter_libs---v045)
 - [`powersync_attachments_helper` - `v0.6.18+1`](#powersync_attachments_helper---v06181)
 - [`powersync_sqlcipher` - `v0.1.4+1`](#powersync_sqlcipher---v0141)
 - [`powersync` - `v1.11.3`](#powersync---v1113)

Packages with dependency updates only:

> Packages listed below depend on other packages in this workspace that have had changes. Their versions have been incremented to bump the minimum dependency versions of the packages they depend upon in this project.

 - `powersync_attachments_helper` - `v0.6.18+1`
 - `powersync_sqlcipher` - `v0.1.4+1`
 - `powersync` - `v1.11.3`

---

#### `powersync_core` - `v1.1.3`

 - Add explicit casts in sync service, avoiding possible issues with dart2js optimizations.

#### `powersync_flutter_libs` - `v0.4.5`

 - Update core extension to 0.3.10 in preparation for bucket priorities.


## 2025-01-28

### Changes

---

Packages with breaking changes:

 - There are no breaking changes in this release.

Packages with other changes:

 - [`powersync_core` - `v1.1.2`](#powersync_core---v112)
 - [`powersync_attachments_helper` - `v0.6.18`](#powersync_attachments_helper---v0618)
 - [`powersync_sqlcipher` - `v0.1.4`](#powersync_sqlcipher---v014)
 - [`powersync` - `v1.11.2`](#powersync---v1112)

Packages with dependency updates only:

> Packages listed below depend on other packages in this workspace that have had changes. Their versions have been incremented to bump the minimum dependency versions of the packages they depend upon in this project.

 - `powersync_attachments_helper` - `v0.6.18`
 - `powersync_sqlcipher` - `v0.1.4`
 - `powersync` - `v1.11.2`

---

#### `powersync_core` - `v1.1.2`

 - Web: Support running in contexts where web workers are unavailable.
 - Web: Fix sync worker logs not being disabled.
 - `powersync_sqlcipher`: Web support.


## 2025-01-16

### Changes

---

Packages with breaking changes:

 - There are no breaking changes in this release.

Packages with other changes:

 - [`powersync` - `v1.11.1`](#powersync---v1111)
 - [`powersync_sqlcipher` - `v0.1.3`](#powersync_sqlcipher---v013)

---

#### `powersync` - `v1.11.1`

 - Fix `statusStream` emitting the same sync status multiple times.

#### `powersync_sqlcipher` - `v0.1.3`

 - Fix `statusStream` emitting the same sync status multiple times.


## 2025-01-06

### Changes

---

Packages with breaking changes:

 - There are no breaking changes in this release.

Packages with other changes:

 - [`powersync_sqlcipher` - `v0.1.2`](#powersync_sqlcipher---v012)
 - [`powersync` - `v1.11.0`](#powersync---v1110)
 - [`powersync_attachments_helper` - `v0.6.17`](#powersync_attachments_helper---v0617)
 - [`powersync_core` - `v1.1.0`](#powersync_core---v110)
 - [`powersync_flutter_libs` - `v0.4.4`](#powersync_flutter_libs---v044)

---

#### `powersync_sqlcipher` - `v0.1.2`

#### `powersync` - `v1.11.0`

 - Increase limit on number of columns per table to 1999.
 - Avoid deleting the $local bucket on connect().

#### `powersync_attachments_helper` - `v0.6.17`

 - Update dependencies.

#### `powersync_core` - `v1.1.0`

 - Increase limit on number of columns per table to 1999.
 - Avoid deleting the $local bucket on connect().

#### `powersync_flutter_libs` - `v0.4.4`

 - powersync-sqlite-core 0.3.8 - increases column limit and fixes view migration issue


## 2024-11-13

### Changes

---

Packages with breaking changes:

 - There are no breaking changes in this release.

Packages with other changes:

 - [`powersync_sqlcipher` - `v0.1.1`](#powersync_sqlcipher---v011)

---

#### `powersync_sqlcipher` - `v0.1.1`

 - Update dependency `powersync_flutter_libs` to v0.4.3


## 2024-11-12

### Changes

---

Packages with breaking changes:

 - There are no breaking changes in this release.

Packages with other changes:

 - [`powersync` - `v1.10.0`](#powersync---v1100)
 - [`powersync_attachments_helper` - `v0.6.16`](#powersync_attachments_helper---v0616)
 - [`powersync_core` - `v1.0.0`](#powersync_core---v100)
 - [`powersync_sqlcipher` - `v0.1.0`](#powersync_sqlcipher---v010)

---

#### `powersync` - `v1.10.0`

 - This package now uses the `powersync_core` package to provide its base functionality.

#### `powersync_attachments_helper` - `v0.6.16`

 - Update a dependency to the latest release.

#### `powersync_core` - `v1.0.0`

 - Dart library for Powersync for use cases such as server-side Dart or non-Flutter Dart environments initial release.

#### `powersync_sqlcipher` - `v0.1.0`

 - PowerSync client SDK for Flutter with encryption enabled using SQLCipher initial release.


## 2024-11-11

### Changes

---

Packages with breaking changes:

 - There are no breaking changes in this release.

Packages with other changes:

 - [`powersync_flutter_libs` - `v0.4.3`](#powersync_flutter_libs---v043)
 - [`powersync` - `v1.9.3`](#powersync---v193)
 - [`powersync_attachments_helper` - `v0.6.15+2`](#powersync_attachments_helper---v06152)

Packages with dependency updates only:

> Packages listed below depend on other packages in this workspace that have had changes. Their versions have been incremented to bump the minimum dependency versions of the packages they depend upon in this project.

 - `powersync` - `v1.9.3`
 - `powersync_attachments_helper` - `v0.6.15+2`

---

#### `powersync_flutter_libs` - `v0.4.3`

 - powersync-sqlite-core 0.3.6 - fixes dangling rows issue


## 2024-11-06

### Changes

---

Packages with breaking changes:

 - There are no breaking changes in this release.

Packages with other changes:

 - [`powersync` - `v1.9.2`](#powersync---v192)
 - [`powersync_attachments_helper` - `v0.6.15+1`](#powersync_attachments_helper---v06151)

Packages with dependency updates only:

> Packages listed below depend on other packages in this workspace that have had changes. Their versions have been incremented to bump the minimum dependency versions of the packages they depend upon in this project.

 - `powersync_attachments_helper` - `v0.6.15+1`

---

#### `powersync` - `v1.9.2`

 - [Web] Automatically flush IndexedDB storage to fix durability issues


## 2024-11-04

### Changes

---

Packages with breaking changes:

 - There are no breaking changes in this release.

Packages with other changes:

 - [`powersync` - `v1.9.1`](#powersync---v191)
 - [`powersync_attachments_helper` - `v0.6.15`](#powersync_attachments_helper---v0615)

---

#### `powersync` - `v1.9.1`

 - Flutter Web Beta release

#### `powersync_attachments_helper` - `v0.6.15`

 - Flutter Web Beta release


## 2024-11-01

### Changes

---

Packages with breaking changes:

 - There are no breaking changes in this release.

Packages with other changes:

 - [`powersync` - `v1.9.0`](#powersync---v190)
 - [`powersync_attachments_helper` - `v0.6.14`](#powersync_attachments_helper---v0614)

---

#### `powersync` - `v1.9.0`

 - **FEAT**: Use a sync worker for web that offloads the task of synchronizing databases to a separate worker, allowing it to be coordinated across tabs even when the database itself is not in a shared worker.

#### `powersync_attachments_helper` - `v0.6.14`

 - Update a dependency to the latest release.

## 2024-10-31

### Changes

---

Packages with breaking changes:

 - There are no breaking changes in this release.

Packages with other changes:

 - [`powersync` - `v1.8.9`](#powersync---v189)
 - [`powersync_attachments_helper` - `v0.6.13`](#powersync_attachments_helper---v0613)
 - [`powersync_flutter_libs` - `v0.4.2`](#powersync_flutter_libs---v042)

---

#### `powersync` - `v1.8.9`

 - **FIX**: Issue where CRUD uploads were not triggered when the SDK reconnected to the PowerSync service after being offline.

#### `powersync_attachments_helper` - `v0.6.13`

 - Update a dependency to the latest release.

#### `powersync_flutter_libs` - `v0.4.2`

 - Update a dependency to the latest release.


## 2024-10-21

### Changes

---

Packages with breaking changes:

 - There are no breaking changes in this release.

Packages with other changes:

 - [`powersync` - `v1.8.8`](#powersync---v188)
 - [`powersync_attachments_helper` - `v0.6.12`](#powersync_attachments_helper---v0612)
 - [`powersync_flutter_libs` - `v0.4.1`](#powersync_flutter_libs---v041)

---

#### `powersync` - `v1.8.8`

 - Update dependency `powersync_flutter_libs`

#### `powersync_attachments_helper` - `v0.6.12`

 - Update a dependency to the latest release.

#### `powersync_flutter_libs` - `v0.4.1`

 - powersync-sqlite-core v0.3.4

## 2024-10-17

### Changes

---

Packages with breaking changes:

 - There are no breaking changes in this release.

Packages with other changes:

 - [`powersync` - `v1.8.7`](#powersync---v187)
 - [`powersync_attachments_helper` - `v0.6.11`](#powersync_attachments_helper---v0611)

---

#### `powersync` - `v1.8.7`

 - **FIX**: Validate duplicate table names. ([47f71888](https://github.com/powersync-ja/powersync.dart/commit/47f71888e9adcdcec08c8ee59cb46ac52bd46640))

#### `powersync_attachments_helper` - `v0.6.11`

 - Update a dependency to the latest release.


## 2024-10-14

### Changes

---

Packages with breaking changes:

 - There are no breaking changes in this release.

Packages with other changes:

 - [`powersync` - `v1.8.6`](#powersync---v186)
 - [`powersync_attachments_helper` - `v0.6.10`](#powersync_attachments_helper---v0610)

---

#### `powersync` - `v1.8.6`

 - Update dependency `sqlite_async` to v0.9.0

#### `powersync_attachments_helper` - `v0.6.10`

 - Update a dependency to the latest release.


## 2024-10-14

### Changes

---

Packages with breaking changes:

 - There are no breaking changes in this release.

Packages with other changes:

 - [`powersync` - `v1.8.5`](#powersync---v185)
 - [`powersync_attachments_helper` - `v0.6.9`](#powersync_attachments_helper---v069)
 - [`powersync_flutter_libs` - `v0.4.0`](#powersync_flutter_libs---v040)

---

#### `powersync` - `v1.8.5`

 - Update dependency `powersync_flutter_libs`

#### `powersync_attachments_helper` - `v0.6.9`

 - Update a dependency to the latest release.

#### `powersync_flutter_libs` - `v0.4.0`

 - powersync-sqlite-core v0.3.0


## 2024-10-01

### Changes

---

Packages with breaking changes:

 - There are no breaking changes in this release.

Packages with other changes:

 - [`powersync` - `v1.8.4`](#powersync---v184)
 - [`powersync_attachments_helper` - `v0.6.8`](#powersync_attachments_helper---v068)

---

#### `powersync` - `v1.8.4`

 - **FEAT**: Added a warning if connector `uploadData` functions don't process CRUD items completely.

#### `powersync_attachments_helper` - `v0.6.8`

 - Update a dependency to the latest release.


## 2024-09-30

### Changes

---

Packages with breaking changes:

 - There are no breaking changes in this release.

Packages with other changes:

 - [`powersync` - `v1.8.3`](#powersync---v183)
 - [`powersync_attachments_helper` - `v0.6.7`](#powersync_attachments_helper---v067)

---

#### `powersync` - `v1.8.3`

 - **FIX**: Pass maxReaders parameter to `PowerSyncDatabase.withFactory()`.

#### `powersync_attachments_helper` - `v0.6.7`

 - Update a dependency to the latest release.


## 2024-09-13

### Changes

---

Packages with breaking changes:

 - There are no breaking changes in this release.

Packages with other changes:

 - [`powersync_attachments_helper` - `v0.6.6`](#powersync_attachments_helper---v066)

---

#### `powersync_attachments_helper` - `v0.6.6`

 - Update a dependency to the latest release.


## 2024-09-09

### Changes

---

Packages with breaking changes:

 - There are no breaking changes in this release.

Packages with other changes:

 - [`powersync` - `v1.8.2`](#powersync---v182)
 - [`powersync_attachments_helper` - `v0.6.5+3`](#powersync_attachments_helper---v0653)

Packages with dependency updates only:

> Packages listed below depend on other packages in this workspace that have had changes. Their versions have been incremented to bump the minimum dependency versions of the packages they depend upon in this project.

 - `powersync_attachments_helper` - `v0.6.5+3`

---

#### `powersync` - `v1.8.2`

 - Added `refreshSchema()`, allowing queries and watch calls to work against updated schemas.


## 2024-09-09

### Changes

---

Packages with breaking changes:

 - There are no breaking changes in this release.

Packages with other changes:

 - [`powersync_flutter_libs` - `v0.3.0`](#powersync_flutter_libs---v023)

---

#### `powersync_flutter_libs` - `v0.3.0`

 - powersync-sqlite-core v0.2.1


## 2024-09-09

### Changes

---

Packages with breaking changes:

 - There are no breaking changes in this release.

Packages with other changes:

 - [`powersync` - `v1.8.1`](#powersync---v181)

---

#### `powersync` - `v1.8.1`

 - Fix powersync_flutter_libs dependency


## 2024-09-06

### Changes

---

Packages with breaking changes:

- There are no breaking changes in this release.

Packages with other changes:

- [`powersync` - `v1.8.0`](#powersync---v180)

---

#### `powersync` - `v1.8.0`

- Requires `journeyapps/powersync-service` v0.5.0 or later when self-hosting
- Use powersync-sqlite-core v0.2.1
- Customize `User-Agent` header
- Add `client_id` parameter to sync requests
- Persist `lastSyncedAt`
- Emit update notifications for watch queries on `disconnectAndClear()`
- Validate that the `powersync-sqlite-core` version number is in a compatible range of `^0.2.0`
- Always cast `target_op` (write checkpoints) to ensure it's an integer
- Sync optimizations for MOVE and REMOVE operations

## 2024-08-23

### Changes

---

Packages with breaking changes:

- There are no breaking changes in this release.

Packages with other changes:

- [`powersync` - `v1.7.0`](#powersync---v170)
- [`powersync_attachments_helper` - `v0.6.5+1`](#powersync_attachments_helper---v0651)

Packages with dependency updates only:

> Packages listed below depend on other packages in this workspace that have had changes. Their versions have been incremented to bump the minimum dependency versions of the packages they depend upon in this project.

- `powersync_attachments_helper` - `v0.6.5+1`

---

#### `powersync` - `v1.7.0`

- **FEAT**: Include schema validation check
- **FEAT**: Include new table check for maximum number of columns allowed

## 2024-08-21

### Changes

---

Packages with breaking changes:

- There are no breaking changes in this release.

Packages with other changes:

- [`powersync` - `v1.6.7`](#powersync---v167)
- [`powersync_attachments_helper` - `v0.6.5`](#powersync_attachments_helper---v065)
- [`powersync_flutter_libs` - `v0.2.2`](#powersync_flutter_libs---v022)

---

#### `powersync` - `v1.6.7`

- **CHORE**: Update dependency powersync_flutter_libs

#### `powersync_attachments_helper` - `v0.6.5`

- Update a dependency to the latest release.

#### `powersync_flutter_libs` - `v0.2.2`

- **FIX**: Prebundling downloaded core binaries.

## 2024-08-21

### Changes

---

Packages with breaking changes:

- There are no breaking changes in this release.

Packages with other changes:

- [`powersync` - `v1.6.6`](#powersync---v166)
- [`powersync_attachments_helper` - `v0.6.4`](#powersync_attachments_helper---v064)
- [`powersync_flutter_libs` - `v0.2.1`](#powersync_flutter_libs---v021)

---

#### `powersync` - `v1.6.6`

- **CHORE**: Update dependency powersync_flutter_libs

#### `powersync_attachments_helper` - `v0.6.4`

- Update a dependency to the latest release.

#### `powersync_flutter_libs` - `v0.2.1`

- **FIX**: Prebundling downloaded core binaries

## 2024-08-19

### Changes

---

Packages with breaking changes:

- There are no breaking changes in this release.

Packages with other changes:

- [`powersync` - `v1.6.5`](#powersync---v165)
- [`powersync_attachments_helper` - `v0.6.3+2`](#powersync_attachments_helper---v0632)
- [`powersync_flutter_libs` - `v0.2.0`](#powersync_flutter_libs---v020)

Packages with dependency updates only:

> Packages listed below depend on other packages in this workspace that have had changes. Their versions have been incremented to bump the minimum dependency versions of the packages they depend upon in this project.

- `powersync_attachments_helper` - `v0.6.3+2`

---

#### `powersync` - `v1.6.5`

- **CHORE**: Update dependency `powersync_flutter_libs`

#### `powersync_flutter_libs` - `v0.2.0`

- **FEAT**: Prebundle downloaded core binaries

## 2024-08-06

### Changes

---

Packages with breaking changes:

- There are no breaking changes in this release.

Packages with other changes:

- [`powersync` - `v1.6.4`](#powersync---v164)
- [`powersync_attachments_helper` - `v0.6.3+1`](#powersync_attachments_helper---v0631)

Packages with dependency updates only:

> Packages listed below depend on other packages in this workspace that have had changes. Their versions have been incremented to bump the minimum dependency versions of the packages they depend upon in this project.

- `powersync_attachments_helper` - `v0.6.3+1`

---

#### `powersync` - `v1.6.4`

- **FIX**: `hasSynced` status should be reset after `disconnectAndClear` has been called. ([5e12a079](https://github.com/powersync-ja/powersync.dart/commit/5e12a07918ca16d3dcf90f26a42c5a61c09fb978))

## 2024-07-31

### Changes

---

Packages with breaking changes:

- There are no breaking changes in this release.

Packages with other changes:

- [`powersync` - `v1.6.3`](#powersync---v163)
- [`powersync_attachments_helper` - `v0.6.3`](#powersync_attachments_helper---v063)

---

#### `powersync` - `v1.6.3`

- **FIX**: Move JS to dev dependencies and lower version range ">=0.6.7 <0.8.0"

#### `powersync_attachments_helper` - `v0.6.3`

- Update a dependency to the latest release.

## 2024-07-30

### Changes

---

Packages with breaking changes:

- There are no breaking changes in this release.

Packages with other changes:

- [`powersync` - `v1.6.2`](#powersync---v162)
- [`powersync_attachments_helper` - `v0.6.2`](#powersync_attachments_helper---v062)

---

#### `powersync` - `v1.6.2`

- **FEAT**: Introduces a custom script to download the sqlite3 wasm and powersync worker files. The command `dart run powersync:setup_web` must be run in the application's folder.

#### `powersync_attachments_helper` - `v0.6.2`

- Update a dependency to the latest release.

## 2024-07-29

### Changes

---

Packages with breaking changes:

- There are no breaking changes in this release.

Packages with other changes:

- [`powersync` - `v1.6.1`](#powersync---v161)
- [`powersync_attachments_helper` - `v0.6.1`](#powersync_attachments_helper---v061)

---

#### `powersync` - `v1.6.1`

- **FIX**: Reintroduce waitForFirstSync.

#### `powersync_attachments_helper` - `v0.6.1`

- Update a dependency to the latest release.

## 2024-07-25

### Changes

---

Packages with breaking changes:

- There are no breaking changes in this release.

Packages with other changes:

- [`powersync` - `v1.6.0`](#powersync---v160)
- [`powersync_attachments_helper` - `v0.6.0`](#powersync_attachments_helper---v060)

Packages with dependency updates only:

> Packages listed below depend on other packages in this workspace that have had changes. Their versions have been incremented to bump the minimum dependency versions of the packages they depend upon in this project.

- `powersync_attachments_helper` - `v0.6.0`

---

#### `powersync` - `v1.6.0`

- `powersync` web support is now included in the standard release but remains in alpha. Web support may have some limitations or bugs.

## 2024-07-18

### Changes

---

Packages with breaking changes:

- There are no breaking changes in this release.

Packages with other changes:

- [`powersync` - `v1.6.0-alpha.1`](#powersync---v160-alpha1)
- [`powersync_attachments_helper` - `v0.6.0-alpha.1`](#powersync_attachments_helper---v060-alpha1)

Packages with dependency updates only:

> Packages listed below depend on other packages in this workspace that have had changes. Their versions have been incremented to bump the minimum dependency versions of the packages they depend upon in this project.

- `powersync_attachments_helper` - `v0.6.0-alpha.1`

---

#### `powersync` - `v1.6.0-alpha.1`

- Added support for client parameters when connecting.
- Fix watch query parameter `triggerOnTables` to prepend powersync view names.
- Upgrade dependency `sqlite_async` to version 0.8.1.
- Fix issue where `hasSynced` is cleared when offline.

## 2024-07-16

### Changes

---

- [`powersync` - `v1.5.5`](#powersync---v155)
- [`powersync_attachments_helper` - `v0.5.1+1`](#powersync_attachments_helper---v0511)

#### `powersync` - `v1.5.5`

- Fix issue where `hasSynced` is cleared when offline.

## 2024-07-10

### Changes

---

Packages with breaking changes:

- There are no breaking changes in this release.

Packages with other changes:

- [`powersync` - `v1.3.0-alpha.9`](#powersync---v130-alpha9)
- [`powersync_attachments_helper` - `v0.3.0-alpha.4`](#powersync_attachments_helper---v030-alpha4)

Packages with dependency updates only:

> Packages listed below depend on other packages in this workspace that have had changes. Their versions have been incremented to bump the minimum dependency versions of the packages they depend upon in this project.

- `powersync_attachments_helper` - `v0.3.0-alpha.4`

---

#### `powersync` - `v1.3.0-alpha.9`

- Updated sqlite_async to use Navigator locks for limiting sync stream implementions in multiple tabs

## 2024-07-04

### Changes

---

Packages with breaking changes:

- There are no breaking changes in this release.

Packages with other changes:

- [`powersync` - `v1.3.0-alpha.8`](#powersync---v130-alpha8)
- [`powersync_attachments_helper` - `v0.3.0-alpha.3`](#powersync_attachments_helper---v030-alpha3)

Packages with dependency updates only:

> Packages listed below depend on other packages in this workspace that have had changes. Their versions have been incremented to bump the minimum dependency versions of the packages they depend upon in this project.

- `powersync_attachments_helper` - `v0.3.0-alpha.3`

---

#### `powersync` - `v1.3.0-alpha.8`

- **FIX**(powersync-attachements-helper): pubspec file (#29).
- **DOCS**: update readme and getting started (#51).

## 2024-05-30

### Changes

---

Packages with breaking changes:

- [`powersync_attachments_helper` - `v0.3.0-alpha.2`](#powersync_attachments_helper---v030-alpha2)

Packages with other changes:

- [`powersync` - `v1.3.0-alpha.5`](#powersync---v130-alpha5)

---

#### `powersync_attachments_helper` - `v0.3.0-alpha.2`

- **FIX**: reset isProcessing when exception is thrown during sync process. (#81).
- **FIX**: attachment queue duplicating requests (#68).
- **FIX**(powersync-attachements-helper): pubspec file (#29).
- **FEAT**(attachments): add error handlers (#65).
- **DOCS**: update readmes (#38).
- **BREAKING** **FEAT**(attachments): cater for subdirectories in storage (#78).

#### `powersync` - `v1.3.0-alpha.5`

- **FIX**(powersync-attachements-helper): pubspec file (#29).
- **DOCS**: update readme and getting started (#51).

## 2024-03-05

### Changes

---

Packages with breaking changes:

- There are no breaking changes in this release.

Packages with other changes:

- [`powersync` - `v1.3.0-alpha.3`](#powersync---v130-alpha3)
- [`powersync_attachments_helper` - `v0.3.0-alpha.2`](#powersync_attachments_helper---v030-alpha2)

Packages with dependency updates only:

> Packages listed below depend on other packages in this workspace that have had changes. Their versions have been incremented to bump the minimum dependency versions of the packages they depend upon in this project.

- `powersync_attachments_helper` - `v0.3.0-alpha.2`

---

#### `powersync` - `v1.3.0-alpha.3`

- Fixed issue where disconnectAndClear would prevent subsequent sync connection on native platforms and would fail to clear the database on web.

## 2024-02-15

### Changes

---

Packages with breaking changes:

- There are no breaking changes in this release.

Packages with other changes:

- [`powersync` - `v1.3.0-alpha.2`](#powersync---v130-alpha2)
- [`powersync_attachments_helper` - `v0.3.0-alpha.2`](#powersync_attachments_helper---v030-alpha2)

Packages with dependency updates only:

> Packages listed below depend on other packages in this workspace that have had changes. Their versions have been incremented to bump the minimum dependency versions of the packages they depend upon in this project.

- `powersync_attachments_helper` - `v0.3.0-alpha.2`

---

#### `powersync` - `v1.3.0-alpha.2`

- **FIX**(powersync-attachements-helper): pubspec file (#29).
- **DOCS**: update readme and getting started (#51).
- `powersync_attachments_helper` - `v0.5.1+1`
