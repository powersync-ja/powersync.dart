---
name: powersync-sqlite-extensions
description: Loading custom SQLite extensions (vector search, FTS5 tokenizers, etc.) with PowerSync across all SDKs and platforms
metadata:
  tags: sqlite, extensions, vector-search, sqlite-vec, fts5, loadExtension, PersistentConnectionFactory, MDSQLiteOptions, LoadPowerSyncExtension, SqliteExtension, wa-sqlite, wasm, dart-ffi, cinterops, custom-extension
---

# SQLite Extensions with PowerSync

> **Load this section only when** the operator wants to use a custom SQLite extension (for example `sqlite-vec` for vector search, a custom FTS5 tokenizer, or any run-time loadable extension) with a PowerSync SDK.

PowerSync SDKs build on SQLite, so most SQLite extensions work with PowerSync. The setup is platform-specific. Use the section matching the target SDK.

| Resource | Description |
|----------|-------------|
| [SQLite Extensions docs](https://docs.powersync.com/client-sdks/advanced/sqlite-extensions) | Full per-SDK guidance with examples, consult when the inline examples below don't cover your case. |
| [SQLite Run-Time Loadable Extensions](https://sqlite.org/loadext.html) | SQLite's official extension loading API reference. |

## Dart / Flutter

### Native (Android, iOS, macOS, desktop)

For native targets, load extensions via `dart:ffi` and build hooks.

The [`sqlite3` package provides a complete example](https://github.com/simolus3/sqlite3.dart/tree/main/sqlite3/example/custom_extension) using build hooks to link extensions. After following that example, call the generated extension method (for example, `sqlite3.loadSqliteVectorExtension()`) before opening any PowerSync database.

### Web (Dart / Flutter)

Loading extensions on the web requires a custom `sqlite3.wasm` build because dynamic linking is not available in WebAssembly. PowerSync does not directly support this.

If you need it: follow the [sqlite3 WASM build instructions](https://github.com/simolus3/sqlite3.dart/tree/main/sqlite3_wasm_build) and mirror the pattern in [PowerSync's own WASM build](https://github.com/powersync-ja/powersync.dart/tree/main/packages/sqlite3_wasm_build), calling the extension's entrypoint in `sqlite3_os_init`.

## JavaScript / TypeScript

### Web (`@powersync/web`)

Loading extensions requires a custom `wa-sqlite` WebAssembly build. PowerSync [forks wa-sqlite](https://github.com/powersync-ja/wa-sqlite); to add a custom extension, patch the build definitions in that fork and add an npm override for `@journeyapps/wa-sqlite`. This is not directly supported.

### React Native (OP-SQLite)

OP-SQLite has built-in support for custom extensions. Follow the [OP-SQLite extension docs](https://op-engineering.github.io/op-sqlite/docs/api#loading-extensions) for building and bundling extensions with your app.

### Node.js

Use `better-sqlite3`'s `loadExtension` method. Because `@powersync/node` runs the database on a worker, loading an extension requires a custom worker:

```typescript
// custom.worker.ts
import Database from 'better-sqlite3';
import { startPowerSyncWorker } from '@powersync/node/worker.js';

async function resolveBetterSqlite3() {
  class DatabaseWithExtension extends Database {
    constructor(...args: any[]) {
      super(...args);
      this.loadExtension('libyourExtension.dylib');
    }
  }
  return DatabaseWithExtension;
}

startPowerSyncWorker({ loadBetterSqlite3: resolveBetterSqlite3 });
```

Reference that worker when creating the database:

```typescript
const db = new PowerSyncDatabase({
  schema: AppSchema,
  database: {
    dbFilename: 'app.db',
    openWorker: (_, options) =>
      new Worker(new URL('./custom.worker.js', import.meta.url), options),
  },
});
```

### Capacitor

`@capacitor-community/sqlite` does not support loading extensions directly.

- **Android:** Use the [`load_extension`](https://sqlite.org/lang_corefunc.html#load_extension) SQL function. Build and bundle the extension following the React Native or Kotlin approach.
- **iOS:** Follow the Swift approach and expose a Swift helper method that loads the extension, then call it from JavaScript.

## Kotlin

Use a custom [`PersistentConnectionFactory`](https://powersync-ja.github.io/powersync-kotlin/common/com.powersync/-persistent-connection-factory/index.html) to load extensions when PowerSync opens a SQLite connection.

For Android and JVM targets:

```kotlin
internal class MyOpenFactory : DriverBasedInMemoryFactory<BundledSQLiteDriver>(
    createBundledDriver()
), PersistentConnectionFactory {

    override fun openConnection(path: String, openFlags: Int): SQLiteConnection =
        driver.open(path, openFlags)

    override fun resolveDefaultDatabasePath(dbFilename: String): String {
        TODO("On Android: context.getDatabasePath(dbFilename).path")
    }

    private companion object {
        fun createBundledDriver(): BundledSQLiteDriver =
            BundledSQLiteDriver().also {
                it.addPowerSyncExtension()
                it.addExtension("my_custom_extension_file")
            }
    }
}
```

Platform-specific bundling:

- **JVM:** Bundle the extension as a resource. Use [`ClassLoader`](https://github.com/powersync-ja/powersync-kotlin/blob/main/common/src/jvmMain/kotlin/com/powersync/ExtractLib.kt) to extract it to a temporary file before passing the path to `addExtension`.
- **Android:** Build with the [Android NDK](https://developer.android.com/ndk) and pass the library name directly to `addExtension` (`System.loadLibrary` will resolve it).
- **Kotlin/Native:** Use [cinterops](https://kotlinlang.org/docs/native-c-interop.html) to build the extension as a library. Call its entrypoint via [`sqlite3_auto_extension`](https://github.com/powersync-ja/powersync-kotlin/blob/main/common/src/nativeMain/kotlin/com/powersync/ConnectionFactory.native.kt) before opening any PowerSync database.

## .NET

Set `MDSQLiteOptions.Extensions` to an array of `SqliteExtension` objects to load custom extensions. You are responsible for building and bundling extension files so they can be loaded.

If you need to disable auto-loading of the PowerSync core extension, set `MDSQLiteOptions.LoadPowerSyncExtension` to `false`. When doing so, one of the extensions in `MDSQLiteOptions.Extensions` must contain a build of the PowerSync core extension. Running the .NET SDK without the core extension, or with an outdated version, is not supported.

## Rust / Tauri

Your app links SQLite directly, so standard SQLite extension APIs apply.

For `sqlite-vec`, depend on the [`sqlite-vec` crate](https://crates.io/crates/sqlite-vec) and call `sqlite3_vec_init()` before opening a PowerSync database.

For other extensions:

- Statically linked: use [`register_auto_extension`](https://docs.rs/rusqlite/latest/rusqlite/auto_extension/fn.register_auto_extension.html) with the extension's entrypoint function.
- Dynamically loaded: call [`load_extension`](https://docs.rs/rusqlite/0.39.0/rusqlite/struct.Connection.html#method.load_extension) on a `Connection` before passing it to a `ConnectionPool`.

## Swift

1. Write Swift Package Manager definitions to build and link the extension with your app.
2. Depend on [PowerSync CSQLite](https://github.com/powersync-ja/CSQLite).
3. Add a [module shim](https://github.com/powersync-ja/powersync-swift/tree/main/Sources/PowerSyncCoreShim) target to expose the extension from Swift.
4. Import that target and CSQLite, then [load the extension statically](https://github.com/powersync-ja/powersync-swift/blob/main/Sources/PowerSync/Implementation/sqlite3/registerPowerSyncCoreExtension.swift) before opening a PowerSync database.
