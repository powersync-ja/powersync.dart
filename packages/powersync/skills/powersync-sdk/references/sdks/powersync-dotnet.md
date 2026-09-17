---
name: powersync-dotnet
description: PowerSync .NET SDK — schema, queries, sync lifecycle, and backend connectors
metadata:
  tags: dotnet, csharp, maui, wpf, console, sqlite, offline-first
---

# PowerSync .NET SDK

> **Load this when** building a .NET app (MAUI, WPF, Console) with PowerSync.

## Table of Contents
- [Installation](#installation)
- [Quick Setup](#quick-setup)
- [Query Patterns](#query-patterns)
- [Writes and Transactions](#writes-and-transactions)
- [Sync Status](#sync-status)
- [Sync Streams](#sync-streams)
- [Logging](#logging)
- [Schema Updates](#schema-updates)

Best practices for building apps with the PowerSync .NET SDK.

Supported targets: .NET 9, .NET 8, .NET 6, .NET Standard 2.0, .NET Framework 4.8. Application frameworks: MAUI (iOS, Android, Windows), WPF, Console.

> **Alpha status** — this SDK is currently in alpha. Expect breaking changes and instability. Do not rely on it for production use.

## Installation

For console, WPF, or general .NET projects:

```bash
dotnet add package PowerSync.Common --prerelease
```

For MAUI projects (also requires `PowerSync.Common`):

```bash
dotnet add package PowerSync.Maui --prerelease
dotnet add package PowerSync.Common --prerelease
```

For .NET Framework 4.8 compatibility, add to your `.csproj`:

```xml
<PropertyGroup>
  <RuntimeIdentifiers>win-x86;win-x64</RuntimeIdentifiers>
  <RuntimeIdentifier>win-x64</RuntimeIdentifier>
</PropertyGroup>
<ItemGroup>
  <PackageReference Include="System.Net.Http" Version="4.3.4" />
</ItemGroup>
```

## Quick Setup

### 1. Define Schema

There are two ways to define schemas: **dictionary syntax** (simple) and **attribute syntax** (type-safe, with Dapper integration).

#### Dictionary Syntax

```csharp
using PowerSync.Common.DB.Schema;

var todos = new Table
{
    Name = "todos",
    Columns =
    {
        ["description"] = ColumnType.Text,
        ["list_id"] = ColumnType.Text,
        ["completed"] = ColumnType.Integer, // booleans as INTEGER (0/1)
        ["created_at"] = ColumnType.Text,   // dates as ISO TEXT
    },
    Indexes =
    {
        ["list_idx"] = ["list_id"],
    }
};

var lists = new Table
{
    Name = "lists",
    Columns =
    {
        ["name"] = ColumnType.Text,
        ["owner_id"] = ColumnType.Text,
        ["created_at"] = ColumnType.Text,
    }
};

var schema = new Schema(todos, lists);
```

#### Attribute Syntax

```csharp
using PowerSync.Common.DB.Schema.Attributes;

[Table("todos"), Index("list_idx", ["list_id"])]
public class TodoItem
{
    [Column("id")]
    public string Id { get; set; } = "";

    [Column("description")]
    public string Description { get; set; } = "";

    [Column("list_id")]
    public string ListId { get; set; } = "";

    [Column("completed")]
    public bool Completed { get; set; }  // bool maps to INTEGER automatically

    [Column("created_at")]
    public string CreatedAt { get; set; } = "";
}

[Table("lists")]
public class TodoList
{
    [Column("id")]
    public string Id { get; set; } = "";

    [Column("name")]
    public string Name { get; set; } = "";

    [Column("owner_id")]
    public string OwnerId { get; set; } = "";

    [Column("created_at")]
    public string CreatedAt { get; set; } = "";
}

// Build schema from attributed types
var schema = new Schema(typeof(TodoItem), typeof(TodoList));

// Or mix: new Table(typeof(TodoItem)) also works
```

With attribute syntax, an `id` property of type `string` is **required** on each class but is not added as a column — PowerSync adds `id TEXT PRIMARY KEY` automatically. The `[Column("id")]` attribute maps the property for Dapper deserialization.

Column types: `ColumnType.Text`, `ColumnType.Integer`, `ColumnType.Real` only — no boolean, date, or JSON native types. With attributes, `ColumnType.Inferred` auto-maps C# types (`string` → Text, `bool`/`int`/`long`/`enum` → Integer, `float`/`double` → Real, `decimal`/`DateTime`/`Guid` → Text).

No migrations required. Schema changes apply on next open. New columns start null; removed columns become inaccessible (data remains). Renaming = add new + remove old (data loss).

### Special Table Options

```csharp
// Local-only — not synced, not uploaded, persists across restarts
var drafts = new Table("drafts",
    new Dictionary<string, ColumnType> { ["content"] = ColumnType.Text },
    new TableOptions(localOnly: true));

// Insert-only — writes uploaded, server never sends data back
var logs = new Table("logs",
    new Dictionary<string, ColumnType> { ["message"] = ColumnType.Text },
    new TableOptions(insertOnly: true));

// Track previous values — available as entry.PreviousValues in UploadData
var todos = new Table("todos",
    new Dictionary<string, ColumnType>
    {
        ["description"] = ColumnType.Text,
        ["completed"] = ColumnType.Integer,
    },
    new TableOptions(
        trackPreviousValues: new TrackPreviousOptions
        {
            Columns = new List<string> { "completed" }, // null = track all columns
            OnlyWhenChanged = true
        }
    ));

// Track write metadata — adds _metadata column, available as entry.Metadata in UploadData
var tasks = new Table("tasks",
    new Dictionary<string, ColumnType> { ["title"] = ColumnType.Text },
    new TableOptions(trackMetadata: true));

// Ignore no-op updates (UPDATE that changes no values)
var items = new Table("items",
    new Dictionary<string, ColumnType> { ["name"] = ColumnType.Text },
    new TableOptions(ignoreEmptyUpdates: true));
```

With attribute syntax:

```csharp
[Table("todos", TrackPreviousValues = TrackPrevious.Columns | TrackPrevious.OnlyWhenChanged)]
[Index("list_idx", ["list_id"])]
public class TodoItem
{
    [Column("id")]
    public string Id { get; set; } = "";

    [Column("completed", TrackPrevious = true)] // only this column tracked
    public bool Completed { get; set; }

    [Column("description")]
    public string Description { get; set; } = "";
}

[Table("logs", InsertOnly = true)]
public class LogEntry { /* ... */ }

[Table("drafts", LocalOnly = true)]
public class Draft { /* ... */ }

[Table("tasks", TrackMetadata = true)]
public class Task { /* ... */ }

[Table("items", IgnoreEmptyUpdates = true)]
public class Item { /* ... */ }
```

### 2. Create Backend Connector

```csharp
using PowerSync.Common.Client;
using PowerSync.Common.Client.Connection;
using PowerSync.Common.DB.Crud;

public class MyConnector : IPowerSyncBackendConnector
{
    public async Task<PowerSyncCredentials?> FetchCredentials()
    {
        // Always fetch fresh credentials — do not cache stale tokens
        var token = await myAuthService.GetTokenAsync();
        return new PowerSyncCredentials(
            endpoint: "https://your-instance.powersync.journeyapps.com",
            token: token
        );
    }

    public async Task UploadData(IPowerSyncDatabase database)
    {
        var transaction = await database.GetNextCrudTransaction();
        if (transaction == null) return;

        try
        {
            foreach (var entry in transaction.Crud)
            {
                switch (entry.Op)
                {
                    case UpdateType.PUT:
                        await api.Upsert(entry.Table, entry.Id, entry.OpData!);
                        break;
                    case UpdateType.PATCH:
                        await api.Update(entry.Table, entry.Id, entry.OpData!);
                        break;
                    case UpdateType.DELETE:
                        await api.Delete(entry.Table, entry.Id);
                        break;
                }
            }

            await transaction.Complete(); // MUST call — otherwise the same transaction is returned forever
        }
        catch (Exception ex)
        {
            throw; // PowerSync backs off and retries automatically
        }
    }
}
```

**Fatal upload errors**: If `UploadData` always throws for a bad record, the queue stalls permanently. Detect unrecoverable errors (e.g. constraint violations) and call `await transaction.Complete()` to discard them.

#### CrudEntry Fields

```csharp
entry.Id              // string — row ID
entry.Op              // UpdateType — PUT | PATCH | DELETE
entry.OpData          // Dictionary<string, object>? — changed columns (null for DELETE)
entry.Table           // string — table name
entry.TransactionId   // long? — groups ops from the same WriteTransaction()
entry.PreviousValues  // Dictionary<string, string?>? — requires TrackPreviousValues on table
entry.Metadata        // string? — requires TrackMetadata on table
entry.ClientId        // int — internal client ID for the CRUD entry
```

Op semantics: `PUT` = full insert/replace (all non-null columns), `PATCH` = partial update (changed columns only), `DELETE` = deletion (`OpData` is null).

For batching multiple transactions at once, use `database.GetCrudBatch(limit)`. Both `CrudBatch` and `CrudTransaction` follow the same `Complete()` contract.

### 3. Initialize and Connect

#### Console / WPF

```csharp
using PowerSync.Common.Client;

var db = new PowerSyncDatabase(new PowerSyncDatabaseOptions
{
    Database = new SQLOpenOptions { DbFilename = "app.db" },
    Schema = schema,
});
await db.Init();

// Starts sync stream and UploadData loop in the background (non-blocking)
await db.Connect(connector);

// Wait for first sync before showing data-dependent UI
await db.WaitForFirstSync();
```

#### MAUI

```csharp
using PowerSync.Common.Client;
using PowerSync.Common.MDSQLite;
using PowerSync.Maui.SQLite;

var dbPath = Path.Combine(FileSystem.AppDataDirectory, "app.db");
var factory = new MAUISQLiteDBOpenFactory(new MDSQLiteOpenFactoryOptions
{
    DbFilename = dbPath
});

var db = new PowerSyncDatabase(new PowerSyncDatabaseOptions
{
    Database = factory,
    Schema = schema,
});
await db.Init();

await db.Connect(connector);
```

Use a **single `PowerSyncDatabase` instance** per database file. Multiple instances for the same file cause lock contention and missed watch updates — share via dependency injection.

#### Connection Options

```csharp
await db.Connect(connector, new PowerSyncConnectionOptions(
    @params: new Dictionary<string, object> { ["userId"] = "abc123" }, // sync parameters
    retryDelayMs: 5000,
    crudUploadThrottleMs: 1000,
    appMetadata: new Dictionary<string, string> { ["app_version"] = "1.0.0" }
));
```

#### Disconnect and Clear

```csharp
await db.Disconnect();                    // stop syncing, keep local data
await db.DisconnectAndClear();            // stop syncing, wipe synced tables (e.g. on sign-out)
await db.DisconnectAndClear(clearLocal: false); // wipe synced data but preserve local-only tables
await db.Close();                         // release resources — cannot be reused after this
```

`Disconnect()` — temporary offline, token refresh, app backgrounding. Safe to reconnect as the same user. `DisconnectAndClear()` — user sign-out or account switch, prevents stale data leaking to the next user. `Close()` — app termination, instance cannot be reused after this call.

## Query Patterns

The .NET SDK uses [Dapper](https://github.com/DapperLib/Dapper) for result mapping. Query results are mapped to record types, classes, or `dynamic`.

### Watch Queries (Reactive)

Watch returns an `IAsyncEnumerable<T[]>` that emits new results whenever dependent tables change.

```csharp
public record TodoResult(string id, string description, string list_id, int completed);

// Watch returns IAsyncEnumerable — call synchronously to capture table listener
var watcher = db.Watch<TodoResult>(
    "SELECT * FROM todos WHERE list_id = ? ORDER BY id",
    parameters: [listId]
);

// Consume asynchronously
await foreach (var todos in watcher)
{
    // todos is TodoResult[] — updated on every relevant table change
    UpdateUI(todos);
}
```

With cancellation:

```csharp
var cts = new CancellationTokenSource();
var watcher = db.Watch<TodoResult>(
    "SELECT * FROM todos",
    options: new SQLWatchOptions { Signal = cts.Token }
);

_ = Task.Run(async () =>
{
    await foreach (var results in watcher)
    {
        UpdateUI(results);
    }
}, cts.Token);

// Later: stop watching
cts.Cancel();
```

React to table changes without re-running a query:

```csharp
var onChange = db.OnChange(new SQLWatchOptions { Tables = ["todos", "lists"] });
await foreach (var e in onChange)
{
    Console.WriteLine($"Changed tables: {string.Join(", ", e.ChangedTables)}");
}
```

### One-Time Queries

```csharp
// GetAll — returns T[]
var todos = await db.GetAll<TodoResult>(
    "SELECT * FROM todos WHERE list_id = ?", [listId]);

// Get — returns T, throws if not found
var todo = await db.Get<TodoResult>(
    "SELECT * FROM todos WHERE id = ?", [id]);

// GetOptional — returns T? (null if not found)
var todo = await db.GetOptional<TodoResult>(
    "SELECT * FROM todos WHERE id = ?", [id]);

// Dynamic results (no type parameter)
var rows = await db.GetAll("SELECT * FROM todos");
```

### Result Mapping

With dictionary syntax, use records/classes whose property names match column names:

```csharp
// Simple record — property names must match column names exactly
public record ListResult(string id, string name, string owner_id, string created_at);

var lists = await db.GetAll<ListResult>("SELECT * FROM lists");
```

With attribute syntax, `[Column("column_name")]` maps columns to C# properties and Dapper handles the mapping automatically:

```csharp
// Using the attributed TodoItem class defined in the schema section
var items = await db.GetAll<TodoItem>("SELECT * FROM todos");
```

## Writes and Transactions

```csharp
// Single operation — uuid() is a PowerSync built-in SQLite function
await db.Execute(
    "INSERT INTO lists (id, created_at, name, owner_id) VALUES (uuid(), datetime(), ?, ?)",
    ["My List", userId]);

// Multiple operations atomically — auto-commits, auto-rollbacks on exception
await db.WriteTransaction(async tx =>
{
    await tx.Execute("DELETE FROM lists WHERE id = ?", [listId]);
    await tx.Execute("DELETE FROM todos WHERE list_id = ?", [listId]);
});

// Write transaction with return value
var count = await db.WriteTransaction<int>(async tx =>
{
    await tx.Execute("INSERT INTO lists (id, name, owner_id) VALUES (uuid(), ?, ?)", ["New", userId]);
    var result = await tx.Get<CountResult>("SELECT count(*) as count FROM lists");
    return result.count;
});
```

ID generation — every table has `id TEXT PRIMARY KEY` added automatically:

```csharp
await db.Execute("INSERT INTO todos (id, description) VALUES (uuid(), ?)", ["Buy milk"]);
// or generate in C#:
await db.Execute("INSERT INTO todos (id, description) VALUES (?, ?)", [Guid.NewGuid().ToString(), "Buy milk"]);
```

### Batch Execution

```csharp
// Execute the same statement with multiple parameter sets
await db.ExecuteBatch(
    "INSERT INTO todos (id, description, list_id) VALUES (uuid(), ?, ?)",
    [
        ["Buy milk", listId],
        ["Buy eggs", listId],
        ["Buy bread", listId],
    ]);
```

## Sync Status

```csharp
SyncStatus status = db.CurrentStatus;

status.Connected            // bool — sync stream is active
status.Connecting           // bool
status.DataFlowStatus.Downloading  // bool
status.DataFlowStatus.Uploading    // bool
status.HasSynced            // bool? — null = DB still opening; true = at least one full sync completed
status.LastSyncedAt         // DateTime?
status.DownloadProgress()   // SyncProgress? — non-null only while downloading
status.DataFlowStatus.UploadError    // Exception?
status.DataFlowStatus.DownloadError  // Exception?
```

Observe status changes via event stream:

```csharp
await foreach (var update in db.ListenAsync(cancellationToken))
{
    if (update.StatusChanged != null)
    {
        var s = update.StatusChanged;
        Console.WriteLine($"Connected: {s.Connected}, HasSynced: {s.HasSynced}");
    }
}
```

`HasSynced` persists across app restarts once set.

### Sync Priorities

Buckets can be assigned priorities (lower number = higher priority) on the server. Higher-priority data syncs first. See [Prioritized Sync](https://docs.powersync.com/usage/use-case-examples/prioritized-sync.md).

```csharp
await db.WaitForFirstSync(new PowerSyncDatabase.PrioritySyncRequest { Priority = 1 });

var entry = db.CurrentStatus.StatusForPriority(1);
entry.HasSynced     // bool?
entry.LastSyncedAt  // DateTime?

var progress = db.CurrentStatus.DownloadProgress()?.UntilPriority(1);
progress?.DownloadedFraction    // double 0.0–1.0
progress?.DownloadedOperations  // int
progress?.TotalOperations       // int
```

## Sync Streams

Sync Streams are the recommended way to define what data syncs to each client. See [Sync Config](references/sync-config.md) for server-side configuration (YAML definitions, parameters, CTEs) and [Client-Side Usage](https://docs.powersync.com/sync/streams/client-usage.md) for full examples.

> Sync Streams are currently in alpha in the .NET SDK.

If `auto_subscribe` is not set to `true` in the sync config, subscribe to streams from client code:

```csharp
using PowerSync.Common.Client.Sync.Stream;

// Create a stream handle
ISyncStream stream = db.SyncStream(
    name: "my_orders",
    parameters: new Dictionary<string, object> { ["userId"] = currentUserId }
);

// Subscribe to the stream
ISyncStreamSubscription subscription = await stream.Subscribe(new SyncStreamSubscribeOptions
{
    Ttl = TimeSpan.FromHours(1),                // optional — keep data alive after unsubscribe
    Priority = new StreamPriority(1),           // optional — lower number = higher priority
});

// Wait for this specific stream to complete its first sync
await subscription.WaitForFirstSync();

// Check stream status
SyncStreamStatus? streamStatus = db.CurrentStatus.ForStream(subscription);
streamStatus?.Subscription.HasSynced        // bool
streamStatus?.Subscription.LastSyncedAt     // DateTime?
streamStatus?.Subscription.Active           // bool
streamStatus?.Subscription.IsDefault        // bool
streamStatus?.Subscription.ExpiresAt        // DateTime?
streamStatus?.Progress?.DownloadedFraction  // double

// Unsubscribe when done — TTL starts running after this
subscription.Unsubscribe();

// Or unsubscribe all subscriptions for a stream
await stream.UnsubscribeAll();
```

Same stream name with different parameters creates separate subscriptions. Subscribing while offline is supported — subscriptions are tracked locally and sent on next connect.

## Logging

The SDK accepts an `ILogger` via `PowerSyncDatabaseOptions`:

```csharp
using Microsoft.Extensions.Logging;

ILoggerFactory loggerFactory = LoggerFactory.Create(builder =>
{
    builder.AddConsole();
    builder.SetMinimumLevel(LogLevel.Debug);
});
var logger = loggerFactory.CreateLogger("PowerSync");

var db = new PowerSyncDatabase(new PowerSyncDatabaseOptions
{
    Database = new SQLOpenOptions { DbFilename = "app.db" },
    Schema = schema,
    Logger = logger,
});
```

## Schema Updates

Update the schema at runtime (must be disconnected):

```csharp
await db.Disconnect();
await db.UpdateSchema(newSchema);
await db.Connect(connector);
```

## Additional Resources

Only read these if the content above does not provide enough context for the task.

- [NuGet packages](https://www.nuget.org/profiles/PowerSync) — published packages
- [Full SDK reference](https://docs.powersync.com/client-sdk-references/dotnet.md) — full SDK documentation
- [API reference](https://powersync-ja.github.io/powersync-dotnet/api/PowerSync.html) — generated API docs for all SDK types, methods, and properties
- [CommandLine](https://github.com/powersync-ja/powersync-dotnet/tree/main/demos/CommandLine) — CLI app with real-time data sync example
- [WPF](https://github.com/powersync-ja/powersync-dotnet/tree/main/demos/WPF) — Windows desktop to-do list app example
- [MAUITodo](https://github.com/powersync-ja/powersync-dotnet/tree/main/demos/MAUITodo) — Cross-platform mobile and desktop to-do list example
