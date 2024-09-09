# Change Log

All notable changes to this project will be documented in this file.
See [Conventional Commits](https://conventionalcommits.org) for commit guidelines.

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
