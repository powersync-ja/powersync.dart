---
name: powersync-swift
description: PowerSync Swift SDK: schema, queries, sync lifecycle, ObservableSyncStatus for SwiftUI, app groups/extensions (v1.15+), backend connectors, GRDB ORM support, and Swift Data community integration
metadata:
  tags: swift, ios, macos, grdb, orm, sqlite, offline-first, swift-data, app-groups, observable-sync-status, checkpoint-requests
description: PowerSync Swift SDK: schema, queries, sync lifecycle, checkpoint requests, backend connectors, GRDB ORM support, and Swift Data community integration
---

# PowerSync Swift SDK

> **Load this when** building a Swift app (iOS, macOS) with PowerSync.

Best practices and guidance for building apps with the PowerSync Swift SDK.

| Resource | Description |
|----------|-------------|
| [Swift API reference](https://powersync-ja.github.io/powersync-swift/documentation/powersync/) | Full API reference, consult only when the inline examples don't cover your case. |
| [Supported Platforms](https://docs.powersync.com/resources/supported-platform.md#swift-sdk) | Supported platforms and features, consult for compatibility details. |

## Installation

| Method | Instructions |
|--------|--------------|
| `Package.swift` | [Installation - Package.swift](https://docs.powersync.com/client-sdks/reference/swift.md#package-swift) |
| Xcode | [Installation - Xcode](https://docs.powersync.com/client-sdks/reference/swift.md#xcode) |

## Setup

### 1. Define Schema

```swift
import PowerSync

let lists = Table(
    name: "lists",
    columns: [
        // id column is automatically included
        .text("name"),
        .text("created_at"),
        .text("owner_id")
    ]
)

let todos = Table(
    name: "todos",
    columns: [
        .text("list_id"),
        .text("description"),
        .integer("completed"), // 0 or 1
        .text("created_at"),
        .text("completed_at"),
        .text("created_by"),
        .text("completed_by")
    ],
    indexes: [
        Index(name: "list_id", columns: [IndexedColumn.ascending("list_id")])
    ]
)

let AppSchema = Schema(tables: [lists, todos])
```

See [Define the Client-Side Schema](https://docs.powersync.com/client-sdks/reference/swift.md#1-define-the-client-side-schema) for more information.

### 2. Create Backend Connector

```swift
import PowerSync

@Observable
@MainActor
final class MyConnector: PowerSyncBackendConnectorProtocol {
    private let apiClient: APIClient

    init(apiClient: APIClient) {
        self.apiClient = apiClient
    }

    func fetchCredentials() async throws -> PowerSyncCredentials? {
        let response = try await apiClient.getPowerSyncToken()
        return PowerSyncCredentials(
            endpoint: "https://your-instance.powersync.journeyapps.com",
            token: response.token,
            expiresAt: response.expiresAt
        )
    }

    func uploadData(database: PowerSyncDatabaseProtocol) async throws {
        guard let transaction = try await database.getNextCrudTransaction() else { return }

        do {
            for entry in transaction.crud {
                switch entry.op {
                case .put:
                    var data = entry.opData ?? [:]
                    data["id"] = entry.id
                    try await apiClient.upsert(table: entry.table, id: entry.id, data: data)
                case .patch:
                    guard let opData = entry.opData else { continue }
                    try await apiClient.update(table: entry.table, id: entry.id, data: opData)
                case .delete:
                    try await apiClient.delete(table: entry.table, id: entry.id)
                }
            }
            try await transaction.complete()
        } catch {
            throw error
        }
    }
}
```

Use `getCrudBatch` instead of `getNextCrudTransaction` when uploading large numbers of mutations in bulk.

See [Integrate with your Backend](https://docs.powersync.com/client-sdks/reference/swift.md#3-integrate-with-your-backend) for more information.

### 3. Instantiate and Connect

```swift
@Observable
@MainActor
final class SystemManager {
    let connector = MyConnector()
    let db: PowerSyncDatabaseProtocol

    init() {
        db = PowerSyncDatabase(
            schema: AppSchema,
            dbFilename: "powersync-swift.sqlite"
        )
    }

    func connect() async throws {
        try await db.connect(connector: connector)
    }
}
```

See [Instantiate the PowerSync Database](https://docs.powersync.com/client-sdks/reference/swift.md#2-instantiate-the-powersync-database) for more information.

### App Groups and Extensions (Experimental, v1.15+)

If the database needs to be shared across multiple apps in an app group, pass an absolute path (starting with `/`) as `dbFilename`. The path should point to a file in the app group's [shared container](https://developer.apple.com/documentation/xcode/configuring-app-groups#Access-an-app-groups-shared-container). By default (relative path), the database is stored in `applicationSupportDirectory` with no cross-process sharing.

```swift
let db = PowerSyncDatabase(
    schema: AppSchema,
    dbFilename: "/path/to/app-group-container/powersync.sqlite"
)
```

Multi-process access introduces constraints:

- Call `connect()` in only one process. Two processes connecting to the PowerSync service for the same database wastes resources and can cause concurrency issues.
- SQLite uses file locks for concurrent writes, but the SDK adds no coordination above that. Use [`PRAGMA busy_timeout`](https://sqlite.org/pragma.html#pragma_busy_timeout) to make SQLite wait longer; be ready to handle `SQLITE_BUSY` errors when multiple processes write at the same time.
- Avoid running different Swift SDK versions against the same database file from separate processes. PowerSync-internal migrations can get reverted. App extensions released in the same bundle are not a concern, but separate app group members are.

## Sync Streams

See [sync-config.md](references/sync-config.md) for how to subscribe to Sync Streams when `auto_subscribe` is not set to `true` in the PowerSync Service config.

## Checkpoint Requests (Alpha)

Checkpoint requests let you confirm that the local database has caught up to a specific server state. Use this when you need to know that server changes are available locally: after a local write to wait for the result to sync back, in a pull-to-refresh flow, or when a user opens a link that refers to data that may not have synced yet.

Requires Swift SDK v1.16.0+, PowerSync Service v1.24.0+, and `checkpointMode: .requests()` set in `ConnectOptions`. Support for other SDKs is planned.

```swift
try await database.connect(
    connector: connector,
    options: ConnectOptions(checkpointMode: .requests())
)
```

Checkpoint requests are opt-in. Without `checkpointMode: .requests()`, calling `requestCheckpoint()` throws an error.

### Waiting for the Latest Server Data

Create a checkpoint request, then wait for it to resolve before reading the refreshed data:

```swift
let checkpoint = try await database.requestCheckpoint()
try await checkpoint.waitForSync(timeout: 30)
// Local queries now reflect server state from when requestCheckpoint() was called.
```

`requestCheckpoint()` requires that the database is connected or connecting. If offline, the call suspends until the Service is reachable. Cancel the calling task to stop waiting. The `timeout` passed to `waitForSync(timeout:)` only limits waiting for the checkpoint to apply locally.

### Error Handling

Handle request creation and waiting errors separately when your app needs different recovery behavior:

```swift
do {
    let checkpoint = try await database.requestCheckpoint()
    try await checkpoint.waitForSync(timeout: 30)
} catch CheckpointWaitError.timeout {
    showRefreshMessage("The refresh timed out. Try again.")
} catch CheckpointWaitError.disconnected {
    showRefreshMessage("Reconnect before refreshing again.")
} catch let error as any CheckpointError {
    showRefreshMessage(error.localizedDescription)
}
```

A request remains valid across a disconnect. After reconnecting with `.requests()`, call `waitForSync()` again on the same request. Discard request values after clearing the local PowerSync database, because clearing resets the persisted request state.

`waitForSync()` also fails if the sync client reports an upload or download error. Wait for sync to recover before retrying.

### Relationship to Local Writes

When `.requests()` mode is enabled, the SDK creates an internal request after each upload queue flush. You do not need to call `requestCheckpoint()` for your own writes. If you create a request while writes are pending, waiting on it also waits for those writes to upload and their results to sync back:

```swift
try await database.execute(
    sql: "INSERT INTO tasks (id, description) VALUES (uuid(), ?)",
    parameters: ["Review the project plan"]
)

let checkpoint = try await database.requestCheckpoint()
try await checkpoint.waitForSync(timeout: 30)
// The pending write has uploaded and its server state has synced locally.
```

This behavior relies on `uploadData()` returning only after your backend has committed the uploaded changes to the source database.

### Async Upload Backends (Team/Enterprise)

If `uploadData()` queues writes for later processing rather than committing them synchronously, use `CustomCheckpointRequestConnector`. This requires a `checkpoint_requests` event definition in your sync config and is available on [Team and Enterprise](https://www.powersync.com/pricing) plans. See [Checkpoint Requests](https://docs.powersync.com/client-sdks/advanced/checkpoint-requests) for the full setup guide.

## Query Patterns

See [Using PowerSync: CRUD](https://docs.powersync.com/client-sdks/reference/swift.md#using-powersync-crud-functions) for the full API reference.

### One-Time Queries

```swift
// Fetch all matching rows
let todos = try await db.getAll("SELECT * FROM todos WHERE list_id = ?", parameters: [listId])

// Fetch single row — throws if not found
let todo = try await db.get("SELECT * FROM todos WHERE id = ?", parameters: [id])

// Fetch single row — returns nil if not found
let todo = try await db.getOptional("SELECT * FROM todos WHERE id = ?", parameters: [id])
```

### Reactive Queries

```swift
// Watch a query — emits on every change to the watched tables
for try await todos in db.watch("SELECT * FROM todos WHERE list_id = ?", parameters: [listId]) {
    // update UI
}
```

### Writing Data

```swift
// Single mutation
try await db.execute(
    "INSERT INTO todos (id, description, completed) VALUES (uuid(), ?, ?)",
    parameters: ["New todo", 0]
)

// Multiple related mutations as a single unit
try await db.writeTransaction { tx in
    try await tx.execute("INSERT INTO lists (id, name) VALUES (?, ?)", parameters: [listId, "Shopping"])
    try await tx.execute("INSERT INTO todos (id, list_id, description) VALUES (uuid(), ?, ?)", parameters: [listId, "Milk"])
}
```

## ORM — GRDB

PowerSync Swift officially supports GRDB as an ORM. Requires PowerSync Swift v1.9.0+.

Setup requires a `DatabasePool` with PowerSync config — see [GRDB Setup](https://docs.powersync.com/client-sdks/orms/swift/grdb.md#setup).

```swift
// Define a GRDB record type
struct Todo: Codable, Identifiable, FetchableRecord, PersistableRecord {
    var id: String
    var description: String
    var completed: Int
}

// Read
let todos = try await pool.read { db in
    try Todo.fetchAll(db)
}

// Write
try await pool.write { db in
    var todo = Todo(id: UUID().uuidString, description: "Buy milk", completed: 0)
    try todo.insert(db)
}
```

See [GRDB Architecture](https://docs.powersync.com/client-sdks/orms/swift/grdb.md#architecture) for how the PowerSync + GRDB integration works.

## ORM: Swift Data (Community)

If the project uses Swift Data models, a community-contributed integration is available: [powersync-community/swift-data](https://github.com/powersync-community/swift-data). This integration is community-owned and not officially supported by PowerSync. For setup and usage, see the repository README.
