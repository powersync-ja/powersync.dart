---
name: powersync-kotlin
description: PowerSync Kotlin SDK — schema, queries, sync lifecycle, and backend connectors
metadata:
  tags: kotlin, android, ios, sqlite, offline-first
---

# PowerSync Kotlin SDK

> **Load this when** building a Kotlin app (Android, JVM, KMP) with PowerSync.

## Table of Contents
- [Installation](#installation)
- [Quick Setup](#quick-setup)
- [Query Patterns](#query-patterns)
- [Writes and Transactions](#writes-and-transactions)
- [Compose Integration](#compose-integration)
- [Sync Status](#sync-status)
- [Sync Streams](#sync-streams)
- [Background Sync (Android)](#background-sync-android)

Best practices for building apps with the PowerSync Kotlin SDK.

Supported targets: Android, JVM, iOS, macOS, watchOS, tvOS. Web (JS and WebAssembly) targets have experimental support from v1.14.1. Web is not production-ready; use from a single tab only (multi-tab sync coordination is not functional in this version).

## Installation

Add to `build.gradle.kts`:

```kotlin
kotlin {
    sourceSets {
        commonMain.dependencies {
            api("com.powersync:core:$powersyncVersion")
        }
    }
}
```

For Supabase connector:

```kotlin
commonMain.dependencies {
    implementation("com.powersync:connector-supabase:$powersyncVersion")
}
```

From v1.12.0+ the PowerSync SQLite core extension is statically linked into `com.powersync:core` for all Apple targets (iOS, macOS, tvOS, watchOS), matching Android and JVM. **No CocoaPod or Swift Package dependency on `powersync-sqlite-core` is needed.** Upgrading from an older version? Remove any `pod("powersync-sqlite-core")` entry and any `powersync-sqlite-core-swift` SPM dependency.

For web targets (JS and WebAssembly), use `WebConnectionFactory` to open a PowerSync database. Web support is experimental (added in v1.14.1) and not production-ready. Use from a single tab only; multi-tab sync coordination is not functional.

## Quick Setup

### 1. Define Schema

```kotlin
import com.powersync.db.schema.Column
import com.powersync.db.schema.Index
import com.powersync.db.schema.IndexedColumn
import com.powersync.db.schema.Schema
import com.powersync.db.schema.Table

val todos = Table(
    name = "todos",
    columns = listOf(
        Column.text("description"),
        Column.text("list_id"),
        Column.integer("completed"), // booleans as INTEGER (0/1)
        Column.text("created_at"),   // dates as ISO TEXT
    ),
    indexes = listOf(Index("list_idx", listOf(IndexedColumn("list_id"))))
)

val lists = Table(
    name = "lists",
    columns = listOf(
        Column.text("name"),
        Column.text("owner_id"),
        Column.text("created_at"),
    )
)

val schema = Schema(todos, lists)
```

Column types: `Column.text`, `Column.integer`, `Column.real` only — no boolean, date, or JSON native types.

Do NOT declare an `id` column — PowerSync adds it automatically as `TEXT PRIMARY KEY`. Declaring it throws an `AssertionError`.

No migrations required. Schema changes apply on next open. New columns start null; removed columns become inaccessible (data remains). Renaming = add new + remove old (data loss).

### Special Table Types

```kotlin
// Local-only — not synced, not uploaded, persists across restarts
val drafts = Table.localOnly("drafts", listOf(Column.text("content")))

// Insert-only — writes uploaded, server never sends data back
val logs = Table.insertOnly("logs", listOf(Column.text("message")))

// Track previous values — available as entry.previousValues in uploadData
val todos = Table(
    name = "todos",
    columns = listOf(Column.text("description"), Column.integer("completed")),
    trackPreviousValues = TrackPreviousValuesOptions(
        columnFilter = listOf("completed"), // null = track all columns
        onlyWhenChanged = true
    )
)

// Track write metadata — adds _metadata column, available as entry.metadata in uploadData
val tasks = Table(
    name = "tasks",
    columns = listOf(Column.text("title")),
    trackMetadata = true
)

// Ignore no-op updates (UPDATE that changes no values)
val items = Table(
    name = "items",
    columns = listOf(Column.text("name")),
    ignoreEmptyUpdates = true
)
```

### 2. Create Backend Connector

```kotlin
import com.powersync.connectors.PowerSyncBackendConnector
import com.powersync.connectors.PowerSyncCredentials
import com.powersync.PowerSyncDatabase
import com.powersync.db.crud.UpdateType

class MyConnector : PowerSyncBackendConnector() {
    override suspend fun fetchCredentials(): PowerSyncCredentials {
        // Always fetch fresh credentials — do not cache stale tokens
        return PowerSyncCredentials(
            endpoint = "https://your-instance.powersync.journeyapps.com",
            token = myAuthService.getToken(),
        )
    }

    override suspend fun uploadData(database: PowerSyncDatabase) {
        val transaction = database.getNextCrudTransaction() ?: return
        try {
            for (entry in transaction.crud) {
                when (entry.op) {
                    UpdateType.PUT -> api.upsert(entry.table, entry.id, entry.opData)
                    UpdateType.PATCH -> api.update(entry.table, entry.id, entry.opData)
                    UpdateType.DELETE -> api.delete(entry.table, entry.id)
                }
            }
            transaction.complete(null) // MUST call — otherwise the same transaction is returned forever
        } catch (e: Exception) {
            throw e // PowerSync backs off and retries automatically
        }
    }
}
```

**Fatal upload errors**: If `uploadData` always throws for a bad record, the queue stalls permanently. Detect unrecoverable errors (e.g. constraint violations) and call `transaction.complete(null)` to discard them. The Supabase connector handles Postgres error classes 22, 23, and 42501 automatically.

#### CrudEntry Fields

```kotlin
entry.id             // String — row ID
entry.op             // UpdateType — PUT | PATCH | DELETE
entry.opData         // SqliteRow? — changed columns (null for DELETE)
entry.table          // String — table name
entry.transactionId  // Int? — groups ops from the same writeTransaction()
entry.previousValues // SqliteRow? — requires trackPreviousValues on table
entry.metadata       // String? — requires trackMetadata on table
```

Op semantics: `PUT` = full insert/replace (all non-null columns), `PATCH` = partial update (changed columns only), `DELETE` = deletion (`opData` is null).

For batching multiple transactions at once, use `database.getCrudBatch(limit)` or `database.getCrudTransactions()`. Both follow the same `complete()` contract.

#### Supabase Connector

```kotlin
val connector = SupabaseConnector(
    supabaseUrl = "https://your-project.supabase.co",
    supabaseKey = "your-anon-key",
    powerSyncEndpoint = "https://your-instance.powersync.journeyapps.com",
)
```

`SupabaseConnector` is open — override `uploadCrudEntry` and `handleError` for custom behaviour.

### 3. Initialize and Connect

```kotlin
val db = PowerSyncDatabase(
    factory = factory,       // platform-specific PersistentConnectionFactory
    schema = schema,
    dbFilename = "app.db",
    scope = coroutineScope,
)

// Starts sync stream and uploadData loop in the background (non-blocking)
db.connect(connector)

// Pass sync parameters to the server if needed
db.connect(
    connector = connector,
    params = mapOf("userId" to JsonParam.String("abc123")),
)

// Wait for first sync before showing data-dependent UI
db.waitForFirstSync()
```

Use a **single `PowerSyncDatabase` instance** per database file. Multiple instances for the same file cause lock contention and missed watch updates — share via dependency injection.

#### Disconnect and Clear

```kotlin
db.disconnect()                               // stop syncing, keep local data
db.disconnectAndClear()                       // stop syncing, wipe synced tables (e.g. on sign-out)
db.disconnectAndClear(clearLocal = false, soft = true) // soft-wipe: same user can re-sync faster
db.close()                                    // cannot be reused after this
```

`disconnect()` — temporary offline, token refresh, app backgrounding. Safe to reconnect as the same user. `disconnectAndClear()` — user sign-out or account switch, prevents stale data leaking to the next user. `close()` — app termination, instance cannot be reused after this call.

## Query Patterns

### Watch Queries (Reactive)

```kotlin
import com.powersync.db.getString
import com.powersync.db.getStringOptional
import com.powersync.db.getBoolean

fun watchTodos(listId: String): Flow<List<TodoItem>> =
    db.watch(
        sql = "SELECT * FROM todos WHERE list_id = ? ORDER BY id",
        parameters = listOf(listId),
    ) { cursor ->
        TodoItem(
            id = cursor.getString("id"),
            description = cursor.getString("description"),
            completed = cursor.getBoolean("completed"),
            completedAt = cursor.getStringOptional("completed_at"),
        )
    }
```

Collect in a ViewModel:

```kotlin
viewModelScope.launch {
    db.watch("SELECT * FROM lists") { cursor ->
        ListItem(id = cursor.getString("id"), name = cursor.getString("name"))
    }.collect { _uiState.value = it }
}
```

React to table changes without re-running a query:

```kotlin
db.onChange(tables = setOf("todos", "lists")).collect { changedTables -> }
```

### One-Time Queries

```kotlin
val todos = db.getAll("SELECT * FROM todos WHERE list_id = ?", listOf(listId)) { cursor ->
    TodoItem(id = cursor.getString("id"), ...)
}

val todo  = db.get("SELECT * FROM todos WHERE id = ?", listOf(id)) { cursor -> TodoItem(...) }         // throws if not found
val todo  = db.getOptional("SELECT * FROM todos WHERE id = ?", listOf(id)) { cursor -> TodoItem(...) } // null if not found
```

### SqlCursor (by name)

```kotlin
cursor.getString("description")          // throws if null
cursor.getStringOptional("completed_at") // null if null
cursor.getLong("count")
cursor.getLongOptional("optional_int")
cursor.getDouble("amount")
cursor.getBoolean("completed")
cursor.getBytes("blob_data")
```

Import extension functions from `com.powersync.db`.

## Writes and Transactions

```kotlin
// Single operation — uuid() is a PowerSync built-in SQLite function
db.execute(
    "INSERT INTO lists (id, created_at, name, owner_id) VALUES (uuid(), datetime(), ?, ?)",
    listOf("My List", userId)
)

// Multiple operations atomically — auto-commits, auto-rollbacks on exception
db.writeTransaction { tx ->
    tx.execute("DELETE FROM lists WHERE id = ?", listOf(listId))
    tx.execute("DELETE FROM todos WHERE list_id = ?", listOf(listId))
}
```

ID generation — every table has `id TEXT PRIMARY KEY` added automatically:

```kotlin
db.execute("INSERT INTO todos (id, description) VALUES (uuid(), ?)", listOf("Buy milk"))
// or generate in Kotlin:
import com.benasher44.uuid.uuid4
db.execute("INSERT INTO todos (id, description) VALUES (?, ?)", listOf(uuid4().toString(), "Buy milk"))
```

## Compose Integration

```kotlin
commonMain.dependencies {
    implementation("com.powersync:compose:$powersyncVersion")
}
```

```kotlin
import com.powersync.compose.composeState

@Composable
fun GuardBySync(db: PowerSyncDatabase, content: @Composable () -> Unit) {
    val status by db.currentStatus.composeState()

    if (status.hasSynced == true) {
        content()
        return
    }

    val progress = status.downloadProgress
    if (progress != null) {
        LinearProgressIndicator(progress = progress.fraction)
        Text("Downloaded ${progress.downloadedOperations} of ${progress.totalOperations}")
    } else {
        LinearProgressIndicator() // indeterminate while DB is opening
    }
}
```

## Sync Status

```kotlin
val status = db.currentStatus

status.connected        // Boolean — sync stream is active
status.connecting       // Boolean
status.downloading      // Boolean
status.uploading        // Boolean
status.hasSynced        // Boolean? — null = DB still opening; true = at least one full sync completed
status.lastSyncedAt     // Instant?
status.downloadProgress // SyncDownloadProgress? — non-null only while downloading
status.anyError         // Any? — uploadError ?: downloadError
```

Observe as a Flow:

```kotlin
db.currentStatus.asFlow().collect { status: SyncStatusData -> }
```

`hasSynced` persists across app restarts once set.

### Sync Priorities

Buckets can be assigned priorities (lower number = higher priority) on the server. Higher-priority data syncs first. See [Prioritized Sync](https://docs.powersync.com/usage/use-case-examples/prioritized-sync.md).

```kotlin
db.waitForFirstSync(priority = StreamPriority(1))

val entry = db.currentStatus.statusForPriority(StreamPriority(1))
entry.hasSynced    // Boolean?
entry.lastSyncedAt // Instant?

val progress = status.downloadProgress?.untilPriority(StreamPriority(1))
progress?.fraction             // Float 0.0–1.0
progress?.downloadedOperations // Int
progress?.totalOperations      // Int
```

## Sync Streams

Sync Streams are the recommended way to define what data syncs to each client. See [Sync Config](references/sync-config.md) for server-side configuration (YAML definitions, parameters, CTEs) and [Client-Side Usage](https://docs.powersync.com/sync/streams/client-usage.md) for full Kotlin examples.

If `auto_subscribe` is not set to `true` in the sync config, subscribe to streams from client code:

```kotlin
import com.powersync.utils.JsonParam

// Create a stream handle and subscribe
val stream = db.syncStream(
    name = "my_orders",
    parameters = mapOf("userId" to JsonParam.String(currentUserId)),
)
val subscription = stream.subscribe(
    ttl = 1.hours,                // optional — keep data alive after unsubscribe
    priority = StreamPriority(1), // optional — lower number = higher priority
)

// Wait for this specific stream to complete its first sync
subscription.waitForFirstSync()

// Check stream status
val streamStatus = db.currentStatus.forStream(subscription)
streamStatus?.subscription?.hasSynced       // Boolean
streamStatus?.subscription?.lastSyncedAt    // Instant?
streamStatus?.subscription?.active          // Boolean
streamStatus?.subscription?.isDefault       // Boolean
streamStatus?.subscription?.expiresAt       // Instant?

// Unsubscribe when done — TTL starts running after this
subscription.unsubscribe()

// Or unsubscribe all subscriptions for a stream
stream.unsubscribeAll()
```

Same stream name with different parameters creates separate subscriptions. Subscribing while offline is supported — subscriptions are tracked locally and sent on next connect.

## Background Sync (Android)

Share a single `PowerSyncDatabase` instance between the UI and any foreground service — do not create separate instances or use separate processes.

```kotlin
class SyncService : Service() {
    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val db = (application as MyApp).database
        serviceScope.launch { db.connect(connector) }
        return START_STICKY
    }
    override fun onDestroy() { serviceScope.launch { db.disconnect() } }
}
```

Full example: [`demos/supabase-todolist/androidBackgroundSync`](https://github.com/powersync-ja/powersync-kotlin/tree/main/demos/supabase-todolist/androidBackgroundSync)

## ORM Integrations

- **Room** (beta) — typed queries with compile-time validation: `com.powersync:integration-room:$powersyncVersion` · [Docs](https://docs.powersync.com/client-sdks/orms/kotlin/room.md). If using v1.14.1 or later, upgrade Room to 3.0 before updating the integration.
- **SQLDelight** (beta) — `PowerSyncDriver` implements `SqlDriver`: `com.powersync:powersync-sqldelight:$powersyncVersion` · [Docs](https://docs.powersync.com/client-sdks/orms/kotlin/sqldelight.md)

## Additional Resources

Only read these if the content above does not provide enough context for the task.

- [Kotlin API docs](https://powersync-ja.github.io/powersync-kotlin/) — all available APIs
- [Full SDK reference](https://docs.powersync.com/client-sdk-references/kotlin-multiplatform.md) — full SDK documentation
- [supabase-todolist](https://github.com/powersync-ja/powersync-kotlin/tree/main/demos/supabase-todolist) — PowerSync + Supabase (KMP) example
- [android-supabase-todolist](https://github.com/powersync-ja/powersync-kotlin/tree/main/demos/android-supabase-todolist) — PowerSync + Supabase (Android) example
