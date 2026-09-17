---
name: raw-tables
description: PowerSync Raw Tables — native SQLite tables bypassing JSON views, with multi-SDK examples (JS, Dart, Kotlin, Swift, Rust), triggers, local-only columns, and migration strategies
metadata:
  tags: raw-tables, sqlite, advanced, powersync, javascript, dart, kotlin, swift, rust
---

# Raw Tables

> **Load this when** the project needs native SQLite tables (column types, constraints, indexes, generated columns) instead of PowerSync's default JSON-based views. Works across all SDKs except .NET.

Raw tables let PowerSync sync data directly into native SQLite tables you define, instead of storing data as JSON in `ps_data__<table>` and exposing it via views. This gives full SQLite control and better query performance. See [Raw Tables](https://docs.powersync.com/client-sdks/advanced/raw-tables.md) for the full reference.

## Table of Contents
- [When to Use](#when-to-use-raw-tables)
- [SDK Availability](#sdk-availability)
- [Defining Raw Tables](#defining-raw-tables) (Inferred vs Explicit)
- [Triggers for Local Writes](#triggers-for-local-writes) (Inferred vs Explicit)
- [Local-Only Columns](#local-only-columns)
- [Migrations](#migrations)
- [Caveats](#caveats)

**Status:** Experimental — not covered by semver stability guarantees.

## SDK Availability

| SDK | Min Version | Package |
|-----|-------------|---------|
| JavaScript (Web) | 1.35.0 | `@powersync/web` |
| JavaScript (React Native) | 1.31.0 | `@powersync/react-native` |
| JavaScript (Node) | 0.18.0 | `@powersync/node` |
| Dart / Flutter | 1.18.0 | `package:powersync` |
| Kotlin | 1.11.0 | `com.powersync:core` |
| Swift | 1.12.0 | `PowerSync` |
| Rust | 0.0.4 | `powersync` |
| .NET | — | **Not yet available** |

## When to Use Raw Tables

- Indexes on expressions or `GENERATED` columns (PowerSync's default schema only supports basic column indexes)
- Improved query performance for aggregations (`SUM`, `GROUP BY`) — reads typed columns directly instead of extracting from JSON
- Reduced storage overhead — no JSON object per row
- SQLite constraints (`FOREIGN KEY`, `NOT NULL`, `CHECK`)
- Local-only columns that persist across syncs but never upload

## Defining Raw Tables

You must create the actual SQLite table yourself before calling `connect()`:

```sql
CREATE TABLE IF NOT EXISTS todo_lists (
  id TEXT NOT NULL PRIMARY KEY,
  created_by TEXT NOT NULL,
  title TEXT NOT NULL,
  content TEXT
) STRICT;
```

### Inferred Setup (Recommended)

When the local table structure matches the synced table, the SDK can infer `put`/`delete` statements automatically:

**JavaScript:**
```ts
const mySchema = new Schema({});
mySchema.withRawTables({
  todo_lists: { schema: {} }
});
```

**Dart:**
```dart
const schema = Schema([], rawTables: [
  RawTable.inferred(name: 'todo_lists', schema: RawTableSchema()),
]);
```

**Kotlin:**
```kotlin
val schema = Schema(listOf(
  RawTable(name = "todo_lists", schema = RawTableSchema())
))
```

**Swift:**
```swift
let lists = RawTable(name: "todo_lists", schema: RawTableSchema())
let schema = Schema(lists)
```

**Rust:**
```rust
let table = RawTable::with_schema("todo_lists", RawTableSchema::default());
schema.raw_tables.push(table);
```

Use inferred setup when the local table directly maps to the synced output table. Use explicit setup (below) for transformations, custom defaults, the `_extra` column pattern, or when local and backend table names differ.

### Explicit Setup

Provide `put` and `delete` SQL statements with positional parameters:

**JavaScript:**
```ts
mySchema.withRawTables({
  todo_lists: {
    put: {
      sql: 'INSERT OR REPLACE INTO todo_lists (id, created_by, title, content) VALUES (?, ?, ?, ?)',
      params: ['Id', { Column: 'created_by' }, { Column: 'title' }, { Column: 'content' }]
    },
    delete: {
      sql: 'DELETE FROM todo_lists WHERE id = ?',
      params: ['Id']
    }
  }
});
```

**Dart:**
```dart
RawTable(
  name: 'todo_lists',
  put: PendingStatement(
    sql: 'INSERT OR REPLACE INTO todo_lists (id, created_by, title, content) VALUES (?, ?, ?, ?)',
    params: [.id(), .column('created_by'), .column('title'), .column('content')],
  ),
  delete: PendingStatement(sql: 'DELETE FROM todo_lists WHERE id = ?', params: [.id()]),
)
```

**Kotlin:**
```kotlin
RawTable(
  name = "todo_lists",
  put = PendingStatement(
    "INSERT OR REPLACE INTO todo_lists (id, created_by, title, content) VALUES (?, ?, ?, ?)",
    listOf(PendingStatementParameter.Id, PendingStatementParameter.Column("created_by"),
           PendingStatementParameter.Column("title"), PendingStatementParameter.Column("content"))
  ),
  delete = PendingStatement("DELETE FROM todo_lists WHERE id = ?", listOf(PendingStatementParameter.Id))
)
```

**Swift:**
```swift
RawTable(
  name: "todo_lists",
  put: PendingStatement(
    sql: "INSERT OR REPLACE INTO todo_lists (id, created_by, title, content) VALUES (?, ?, ?, ?)",
    parameters: [.id, .column("created_by"), .column("title"), .column("content")]
  ),
  delete: PendingStatement(sql: "DELETE FROM todo_lists WHERE id = ?", parameters: [.id])
)
```

Parameter types: `Id` = row ID from sync service, `Column("name")` = column value from synced row, `Rest` = remaining columns as JSON (for the `_extra` pattern).

## Triggers for Local Writes

Raw tables need triggers to capture local writes into PowerSync's upload queue (`powersync_crud` virtual table).

### Inferred Triggers (Recommended)

Use `powersync_create_raw_table_crud_trigger` — must be called **after** the `CREATE TABLE`:

**JavaScript:**
```ts
for (const write of ["INSERT", "UPDATE", "DELETE"]) {
  await db.execute("SELECT powersync_create_raw_table_crud_trigger(?, ?, ?)",
    [JSON.stringify(Schema.rawTableToJson(table)), `todo_lists_${write}`, write]);
}
```

**Dart:**
```dart
for (final write in ["INSERT", "UPDATE", "DELETE"]) {
  await db.execute("SELECT powersync_create_raw_table_crud_trigger(?, ?, ?)",
    [json.encode(table), "todo_lists_$write", write]);
}
```

**Kotlin:**
```kotlin
for (write in listOf("INSERT", "UPDATE", "DELETE")) {
  database.execute("SELECT powersync_create_raw_table_crud_trigger(?, ?, ?)",
    listOf(table.jsonDescription(), "todo_lists_$write", write))
}
```

**Swift:**
```swift
for write in ["INSERT", "UPDATE", "DELETE"] {
  try await database.execute(
    sql: "SELECT powersync_create_raw_table_crud_trigger(?, ?, ?)",
    parameters: [lists.jsonDescription(), "todo_lists_\(write)", write])
}
```

### Explicit Triggers

Define triggers manually for full control:

```sql
CREATE TRIGGER todo_lists_insert AFTER INSERT ON todo_lists FOR EACH ROW
BEGIN
  INSERT INTO powersync_crud (op, id, type, data)
  VALUES ('PUT', NEW.id, 'todo_lists', json_object(
    'created_by', NEW.created_by, 'title', NEW.title, 'content', NEW.content));
END;

CREATE TRIGGER todo_lists_update AFTER UPDATE ON todo_lists FOR EACH ROW
BEGIN
  SELECT CASE WHEN (OLD.id != NEW.id) THEN RAISE(FAIL, 'Cannot update id') END;
  INSERT INTO powersync_crud (op, id, type, data)
  VALUES ('PATCH', NEW.id, 'todo_lists', json_object(
    'created_by', NEW.created_by, 'title', NEW.title, 'content', NEW.content));
END;

CREATE TRIGGER todo_lists_delete AFTER DELETE ON todo_lists FOR EACH ROW
BEGIN
  INSERT INTO powersync_crud (op, id, type) VALUES ('DELETE', OLD.id, 'todo_lists');
END;
```

The `powersync_crud` virtual table columns: `op` (PUT/PATCH/DELETE), `id`, `type` (table name), `data` (JSON), `old_values` (optional), `metadata` (optional).

## Local-Only Columns

Raw tables can include columns that exist only on the client — never synced or uploaded. Useful for client preferences, UI state, or local notes.

Add the column to the table and specify `syncedColumns` in the inferred setup so the SDK knows which columns come from the server:

**JavaScript:**
```ts
{ name: 'todo_lists', schema: { syncedColumns: ['created_by', 'title', 'content'] } }
```

**Dart:**
```dart
RawTableSchema(syncedColumns: ['created_by', 'title', 'content'])
```

**Kotlin:**
```kotlin
RawTableSchema(syncedColumns = listOf("created_by", "title", "content"))
```

With explicit setup, use `INSERT ... ON CONFLICT(id) DO UPDATE SET` (not `INSERT OR REPLACE`) to avoid resetting local-only columns on sync. Exclude local-only columns from triggers.

## Migrations

PowerSync's JSON-based tables need no migrations. Raw tables do — you manage the schema.

### Adding a new raw table

If data was already synced before the raw table existed, it's in `ps_untyped`. Copy it after creating the table:

```sql
INSERT INTO my_table (id, col1, col2)
  SELECT id, data ->> 'col1', data ->> 'col2'
  FROM ps_untyped WHERE type = 'my_table';
DELETE FROM ps_untyped WHERE type = 'my_table';
```

Not needed if the raw table was present from the first `connect()` call.

### Adding columns

Three strategies:

1. **Delete and resync:** `disconnectAndClear(soft: true)` → migrate → reconnect. Safest but requires network.
2. **Trigger resync:** `ALTER TABLE ... ADD COLUMN` with a default → `SELECT powersync_trigger_resync(TRUE)`. App stays usable offline with optimistic defaults until resync completes.
3. **`_extra` column pattern:** Store unknown columns as JSON in an `_extra TEXT` column using the `Rest` parameter. Migrate by extracting from `_extra`: `json_extract(_extra, '$.newCol')`.

## Caveats

- **Not available on .NET** yet
- **No automatic column migration** — adding columns requires one of the migration strategies above
- **Foreign keys** — must use `DEFERRABLE INITIALLY DEFERRED`; enable with `PRAGMA foreign_keys = ON`; avoid FK references from high-priority to lower-priority raw tables
- **`disconnectAndClear()` won't clear raw tables** by default — add a `clear` statement to `RawTable` if needed
- **Table name** — the `name` property matches the backend table name, not necessarily the local SQLite table name
- **Drop and re-create triggers** after altering a raw table
