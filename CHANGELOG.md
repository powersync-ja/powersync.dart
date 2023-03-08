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
