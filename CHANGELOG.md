# Change Log

All notable changes to this project will be documented in this file.
See [Conventional Commits](https://conventionalcommits.org) for commit guidelines.

## 2025-01-28

### Changes

---

Packages with breaking changes:

 - There are no breaking changes in this release.

Packages with other changes:

 - [`powersync_core` - `v1.1.2`](#powersync_core---v112)
 - [`powersync_attachments_helper` - `v0.6.17+1`](#powersync_attachments_helper---v06171)
 - [`powersync_sqlcipher` - `v0.1.3+1`](#powersync_sqlcipher---v0131)
 - [`powersync` - `v1.11.2`](#powersync---v1112)

Packages with dependency updates only:

> Packages listed below depend on other packages in this workspace that have had changes. Their versions have been incremented to bump the minimum dependency versions of the packages they depend upon in this project.

 - `powersync_attachments_helper` - `v0.6.17+1`
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
