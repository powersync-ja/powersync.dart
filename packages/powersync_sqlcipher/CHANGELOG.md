## 0.1.5+4

 - Update a dependency to the latest release.

## 0.1.5+3

This updates `powersync_core` to version `1.2.3`, which includes these changes:

 - Introduce locks to avoid duplicate sync streams when multiple instances of the same database are opened.
 - Refactor connect / disconnect internally.
 - Warn when multiple instances of the same database are opened.
 - Fix race condition causing data not to be applied while an upload is in progress.
 - Web: Fix token invalidation logic when a sync worker is used.

## 0.1.5+2

 - Update a dependency to the latest release.

## 0.1.5+1

 - Update a dependency to the latest release.

## 0.1.5

 - Support bucket priorities and partial syncs.

## 0.1.4+1

 - Update a dependency to the latest release.

## 0.1.4

 - Web: Support running in contexts where web workers are unavailable.
 - Web: Fix sync worker logs not being disabled.
 - `powersync_sqlcipher`: Web support.

## 0.1.3

 - Fix `statusStream` emitting the same sync status multiple times.

## 0.1.2

 - Increase limit on number of columns per table to 1999.
 - Avoid deleting the $local bucket on connect().

## 0.1.1

 - Update dependency `powersync_flutter_libs` to v0.4.3

## 0.1.0

 - PowerSync client SDK for Flutter with encryption enabled using SQLCipher initial release
