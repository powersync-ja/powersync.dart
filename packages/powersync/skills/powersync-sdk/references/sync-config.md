---
name: sync-config
description: PowerSync Sync Config — Sync Streams (new), Sync Rules (legacy), parameters, CTEs, common patterns, and migration guidance
metadata:
  tags: sync-streams, sync-rules, sync-config, yaml, buckets, parameters, cte, migration, convex, wildcard-schema, table-metadata, schema-per-tenant, prioritized-sync
---

# Sync Config

> **Load this when** writing or modifying sync configuration — Sync Streams (new) or Sync Rules (legacy). Required for every PowerSync project.

## Table of Contents
**Sync Streams (new):** [Requirements](#requirements) · [File Format](#sync-configyaml-file-format) · [Structure](#structure) · [Stream Options](#stream-options) · [Common Patterns](#common-patterns) · [Query Parameters](#query-parameters) · [CTEs](#common-table-expressions-ctes) · [Migration](#migration) · [Client Usage](#client-usage) · [Advanced Topics](#advanced-topics)
**Sync Rules (legacy):** [Structure](#structure-1) · [Parameter Queries](#parameter-queries) · [Data Queries](#data-queries) · [Supported SQL](#supported-sql-features) · [Common Patterns](#common-patterns-1)

Expert guidance on Sync Config. Sync config is divided into two sections:
1. Sync Streams (new, default) - The latest implementation of Sync Config. New apps should use Sync Streams by default. Prioritize Sync Streams above Sync Rules.
2. Sync Rules (legacy) - The first implementation of Sync Config. New apps should not use Sync Rules, prioritize Sync Streams over Sync Rules.

Critical warnings for fast setup:

- `sync-config.yaml` must begin with a top-level `config:` block containing `edition: 3`.
- If the app is stuck on `Syncing...`, first assume sync config was never deployed or backend setup is incomplete.

# Sync Streams

Sync Streams define exactly which data is synced to each client by using named, SQL-like queries and subscription parameters.

For a full overview, see [Sync Streams Overview](https://docs.powersync.com/sync/streams/overview.md)

## Requirements 

### PowerSync Service
- Self-hosted: v1.20.0+ 
- Cloud: Already met

### Sync Config
Must use config edition 3 in their sync config:
```yaml
config:
  edition: 3
```

### PowerSync SDKs
There are minimum SDK requirements when using Sync Streams in an application. See [Minimum SDK Versions](https://docs.powersync.com/sync/streams/migration.md#minimum-sdk-versions) for a full list for each supported PowerSync SDK.

IMPORTANT
Recent SDK versions ship only the Rust sync client, so no opt-in is needed. On older SDKs (pre `Rust Client Default`), explicitly enable the Rust sync client to use Sync Streams.

## sync-config.yaml File Format

**IMPORTANT:** The `sync-config.yaml` file **must** begin with a top-level `config:` block specifying the edition. Without this wrapper, the PowerSync Service will reject the config. This is the most common deployment error — do not omit it.

```yaml
# powersync/sync-config.yaml — required structure
config:
  edition: 3        # <-- REQUIRED top-level wrapper

streams:
  my_data:
    auto_subscribe: true
    query: SELECT * FROM my_table WHERE user_id = auth.user_id()
```

### Minimal Example

```yaml
config:
  edition: 3

streams:
  posts:
    auto_subscribe: true
    query: SELECT * FROM posts WHERE user_id = auth.user_id()
```

## Structure
```yaml
config:
  edition: 3

streams:
  <stream_name>:
    # CTEs (optional) - define with block inside each stream
    with:
      <cte_name>: SELECT ... FROM ...

    # Behavior options (place above query/queries)
    auto_subscribe: true    # Auto-subscribe clients on connect (default: false)
    priority: 1             # Sync priority (optional). Lower number -> higher priority
    accept_potentially_dangerous_queries: true  # Silence security warnings (default: false)

    # Query options (use one)
    query: SELECT * FROM <table> WHERE ...         # Single query
    queries:                                       # Multiple queries
      - SELECT * FROM <table_a> WHERE ...
      - SELECT * FROM <table_b> WHERE ...
```

> **Bucket limits**: Each unique `(stream name + parameter values)` combination creates one internal bucket. Two per-user limits apply, both defaulting to 1,000: unique bucket count and parameter lookup rows (counted before deduplication, across all streams). If a user exceeds either limit, their sync fails with `PSYNC_S2305`. Read the error message to determine which limit was reached, since the fix differs. To keep bucket count low, use `queries:` (multiple queries in one stream) instead of separate streams. See [Bucket Count](https://docs.powersync.com/sync/streams/bucket-count) for how both limits are calculated.

## Stream Options

Behavior options placed above `query`/`queries` in each stream definition.

### `auto_subscribe` (default: `false`)

When `true`, clients automatically subscribe on connect — no client-side `syncStream()` call needed.

Use for:
- Reference/global data all users need (e.g. `categories`, `app_config`)
- User-scoped data that should always be available offline

Do not use with streams that use `subscription.parameter()`. There is no mechanism to supply the parameter value at auto-subscribe time, so the subscription will produce empty results.

```yaml
streams:
  categories:
    auto_subscribe: true
    query: SELECT * FROM categories

  my_orders:
    auto_subscribe: true
    query: SELECT * FROM orders WHERE user_id = auth.user_id()

  # No auto_subscribe — requires client-supplied parameter
  order_items:
    query: |
      SELECT * FROM order_items
      WHERE order_id = subscription.parameter('order_id')
        AND order_id IN (SELECT id FROM orders WHERE user_id = auth.user_id())
```

### `priority`

Controls sync order. Lower number = higher priority. Valid range is `0`–`3`; default is `3`.

Use when some data must be available sooner (e.g. user profile before activity feed):

```yaml
streams:
  user_profile:
    priority: 1
    auto_subscribe: true
    query: SELECT * FROM profiles WHERE user_id = auth.user_id()

  activity_feed:
    priority: 2
    auto_subscribe: true
    query: SELECT * FROM activity WHERE user_id = auth.user_id()
```

**Priority 0 — special case**: syncs regardless of pending uploads, bypassing the normal upload-consistency guarantee. Use only for append-only/CRDT workloads (e.g. Yjs collaborative editing). Misuse causes flickering or out-of-order data.

The client can also override the priority per-subscription — see [Client Usage](#client-usage).

See [Prioritized Sync](https://docs.powersync.com/sync/advanced/prioritized-sync.md) for full details.

#### First-paint priority split

For an app whose main surface reads a small slice of a large auto-subscribed dataset, split the streams: put the first-screen rows in a small `priority: 1` auto-subscribed stream and keep the bulk at `priority: 2` or lower priority. The first screen can then open at the priority 1 checkpoint instead of waiting for the full first sync.

```yaml
streams:
  inbox_items:
    priority: 1
    auto_subscribe: true
    query: SELECT * FROM items WHERE user_id = auth.user_id() AND folder = 'inbox'

  all_items:
    priority: 2
    auto_subscribe: true
    query: SELECT * FROM items WHERE user_id = auth.user_id()
```

Two nuances:

- Overlap is the point. The same rows appearing in both the hot stream and the bulk stream is safe; a row is only removed from the client when no subscribed stream retains it. Filtering the hot stream on a user-editable column (such as `folder`) is normally risky because an edit can drop the row out of the stream mid-session, but with the bulk stream also subscribed, the row stays local after it leaves the hot slice.
- The client must gate honestly. Only reads fully covered by the hot slice may open at the priority 1 checkpoint. Whole-account aggregates (counts, "all items" lists) must still wait for the full sync, or partial data is presented as complete. The consistency caveats of [Prioritized Sync](https://docs.powersync.com/sync/advanced/prioritized-sync.md), such as stale rows pending deletion, apply as usual.

### `accept_potentially_dangerous_queries` (default: `false`)

PowerSync raises a warning when a stream query uses `subscription.parameter()` or `connection.parameter()` (client-controlled values that are not signed). Set to `true` only after adding an `AND auth.user_id()` guard that scopes the client-supplied value to rows the user actually owns:

```yaml
streams:
  workspace_data:
    accept_potentially_dangerous_queries: true
    query: |
      SELECT * FROM documents
      WHERE workspace_id = subscription.parameter('workspace_id')
        AND workspace_id IN (SELECT id FROM workspaces WHERE owner_id = auth.user_id())
```

The inner `AND` clause is what makes this safe — it prevents a client from requesting data outside their own workspaces.

## Common Patterns

### Global data

No filter — same data for all users. Use `auto_subscribe: true` so clients receive it automatically on connect.

```yaml
streams:
  categories:
    auto_subscribe: true
    query: SELECT * FROM categories

  products:
    auto_subscribe: true
    query: SELECT * FROM products WHERE active = true
```

### Personal data

Filter by the authenticated user using `auth.user_id()`.

```yaml
streams:
  my_notes:
    auto_subscribe: true
    query: SELECT * FROM notes WHERE owner_id = auth.user_id()

  my_orders:
    auto_subscribe: true
    query: SELECT * FROM orders WHERE user_id = auth.user_id()
```

### JOIN

Use `INNER JOIN` to filter rows via a related table (e.g. a membership table):

```yaml
streams:
  team_projects:
    query: |
      SELECT p.*
      FROM projects p
      INNER JOIN team_members tm ON tm.team_id = p.team_id
      WHERE tm.user_id = auth.user_id()
```

For composite-key joins (multiple join columns), use implicit join syntax with multiple `WHERE` equality conditions:

```yaml
streams:
  regional_comments:
    query: |
      SELECT comments.*
      FROM comments, issues
      WHERE comments.issue_id = issues.id
        AND comments.region = issues.region
        AND issues.user_id = auth.user_id()
```

### Subquery

Use `WHERE id IN (SELECT ...)` for indirect access through a related table:

```yaml
streams:
  org_documents:
    query: |
      SELECT * FROM documents
      WHERE org_id IN (
        SELECT org_id FROM org_members WHERE user_id = auth.user_id()
      )
```

### Schema-per-Tenant Data (Postgres)

For multi-tenant Postgres databases with one identical schema per tenant, use a wildcard schema name and the `schema()` function. Prefix `schema()` with the table name or alias from the `FROM` clause. Filter by a JWT claim to restrict each client to its own schema:

```yaml
config:
  edition: 3

streams:
  work_orders:
    query: SELECT * FROM "%".work_orders WHERE work_orders.schema() = auth.parameter('tenant_schema')
```

`"%"` matches every schema; `"tenant_%"` matches every schema whose name starts with `tenant_`. Postgres system schemas are never matched. Rows from all matched schemas sync into a single client-side table named after the table in the query. Requires Sync Streams and PowerSync Service v1.24.0 or later.

**Table metadata functions**: In Sync Streams, these functions return metadata about the source row. Prefix each call with the table name or alias from the `FROM` clause. For example, with `FROM "todos_%" AS todos`, write `todos.table_suffix()`. The functions are available in `WHERE` clauses, `SELECT` columns, and subqueries. Requires Service v1.24.0+.

| Function | Returns |
|----------|---------|
| `schema()` | Source schema name; use with wildcard schemas |
| `table_name()` | Source table name |
| `table_suffix()` | Suffix matched by a wildcard table name; empty on tables without a wildcard name |

If filtering on the wildcard suffix in Sync Streams, use `table_alias.table_suffix()`, not `_table_suffix`. The `_table_suffix` column is available in Sync Rules only.

See [Wildcard Schemas](https://docs.powersync.com/sync/advanced/schemas-and-connections.md#wildcard-schemas-postgres) for setup requirements.

### On-demand with subscription parameter

Client subscribes to a specific resource at runtime. Always include an auth guard.

```yaml
streams:
  list_todos:
    accept_potentially_dangerous_queries: true
    query: |
      SELECT * FROM todos
      WHERE list_id = subscription.parameter('list_id')
        AND list_id IN (SELECT id FROM lists WHERE owner_id = auth.user_id())
```

### ID Column Aliasing

If a source table uses a different primary key name (e.g. MongoDB uses `_id`), alias it to `id` in the query. When the query also selects `*`, write `*` before the alias. The last column with a given name wins; if `*` comes after the alias and the source table has a column with the same name, `*` silently overwrites the alias.

```yaml
streams:
  lists:
    auto_subscribe: true
    queries:
      - SELECT *, _id as id FROM lists
      - SELECT *, _id as id FROM todos WHERE archived = false
```

The same rule applies to composite IDs, e.g. `SELECT *, item_id || '.' || category_id as id FROM item_categories`.

See [Writing Queries](https://docs.powersync.com/sync/streams/queries.md) for JOIN, subquery, and multiple queries per stream details.
See [Examples & Demos](https://docs.powersync.com/sync/streams/examples.md) for complete working app patterns.

## Query Parameters

There are three kinds of query parameters. Choose based on where the value comes from and how often it changes.

### Auth parameters

Values from the signed JWT — the most secure option. Use when filtering by who the user is. These cannot be tampered with by the client.

```yaml
streams:
  my_orders:
    query: SELECT * FROM orders WHERE user_id = auth.user_id()

  tenant_data:
    query: SELECT * FROM records WHERE tenant_id = auth.jwt() ->> 'tenant_id'
```

See [Auth Parameters](https://docs.powersync.com/sync/streams/parameters.md#auth-parameters) for all available JWT claims.

### Subscription parameters

The client chooses what to sync at runtime. Each subscription is independent — a user can have multiple subscriptions to the same stream with different values. Always scope with an auth guard to prevent a client from accessing data they don't own.

```yaml
streams:
  list_todos:
    accept_potentially_dangerous_queries: true
    query: |
      SELECT * FROM todos
      WHERE list_id = subscription.parameter('list_id')
        AND list_id IN (SELECT id FROM lists WHERE owner_id = auth.user_id())
```

See [Subscription Parameters](https://docs.powersync.com/sync/streams/parameters.md#subscription-parameters) for full reference.

### Connection parameters

Apply globally across all streams for the session. Use for values that rarely change, like environment flags or feature toggles. Changing them requires reconnecting.

```yaml
streams:
  config:
    auto_subscribe: true
    query: SELECT * FROM config WHERE env = connection.parameter('environment')
```

See [Connection Parameters](https://docs.powersync.com/sync/streams/parameters.md#connection-parameters) for full reference.

## Common Table Expressions (CTEs)

Reusable query patterns for your Sync Streams. You can create Global and Scoped CTEs. 

Global 
```yaml
with:
  user_orgs: SELECT org_id FROM org_members WHERE user_id = auth.user_id()

streams:
  org_projects:
    query: SELECT * FROM projects WHERE org_id IN user_orgs
  
  org_repositories:
    query: SELECT * FROM repositories WHERE org_id IN user_orgs
  
  org_settings:
    query: SELECT * FROM settings WHERE org_id IN user_orgs
```

Scoped 
```yaml
streams:
  project_data:
    with:
      accessible_projects: |
        SELECT id FROM projects 
        WHERE org_id IN (SELECT org_id FROM org_members WHERE user_id = auth.user_id())
    queries:
      - SELECT * FROM projects WHERE id IN accessible_projects
      - SELECT * FROM tasks WHERE project_id IN accessible_projects
      - SELECT * FROM comments WHERE project_id IN accessible_projects
```

### CTE Limitations

This won't work
```yaml
# This won't work - cte2 cannot reference cte1
with:
  cte1: SELECT org_id FROM org_members WHERE user_id = auth.user_id()
  cte2: SELECT id FROM projects WHERE org_id IN cte1  # Error!

```

For a full breakdown, see [Limitations](https://docs.powersync.com/sync/streams/ctes.md#limitations).

## Migration

There are big differences between Sync Rules and Sync Streams, consider the following when migrating from Sync Rules to Sync Streams. See [Sync Streams Migrations](https://docs.powersync.com/sync/streams/migration.md) for information such as:
- How to migrate
- The tools that can make it easier 
- Understanding the difference between Sync Rules and Sync Streams
- Migration examples for common scenarios

## Client Usage

Client applications subscribe to Sync Streams to start syncing data. See [Client-Side Usage](https://docs.powersync.com/sync/streams/client-usage.md) for a full breakdown.

### TTL (Time-To-Live)

Each subscription has a TTL that keeps data cached after unsubscribing. Default is **24 hours**.

```js
// Default (24h cache after unsubscribe)
const sub = await db.syncStream('todos', { list_id: 'abc' }).subscribe();

// Custom TTL in seconds
const sub = await db.syncStream('todos', { list_id: 'abc' }).subscribe({ ttl: 3600 }); // 1 hour

// Remove data immediately on unsubscribe
const sub = await db.syncStream('todos', { list_id: 'abc' }).subscribe({ ttl: 0 });

// Keep forever
const sub = await db.syncStream('todos', { list_id: 'abc' }).subscribe({ ttl: Infinity });
```

### Priority Override

Override the stream's YAML-defined priority for a specific subscription:

```js
const sub = await db.syncStream('todos', { list_id: 'abc' }).subscribe({ priority: 1 });
```

When multiple components subscribe to the same stream+parameters with different priorities, PowerSync uses the highest priority until all those subscriptions end.

There are examples available for each PowerSync Client SDK.

| SDK                  | Client Usage Reference URL                                                                                         |
|----------------------|-------------------------------------------------------------------------------------------------------------------|
| TypeScript/JavaScript| [Client Usage](https://docs.powersync.com/sync/streams/client-usage.md#typescript%2Fjavascript)                           |
| Dart                 | [Client Usage](https://docs.powersync.com/sync/streams/client-usage.md#dart)                                              |
| Kotlin               | [Client Usage](https://docs.powersync.com/sync/streams/client-usage.md#kotlin)                                            |
| Swift                | [Client Usage](https://docs.powersync.com/sync/streams/client-usage.md#swift)                                             |
| .NET                 | [Client Usage](https://docs.powersync.com/sync/streams/client-usage.md#net)                                               |

### Frameworks 

| Framework                 | Client Usage Reference URL                                                                                         |
|---------------------------|-----------------------------------------------------------------------------------------------------------------|
| React                     | [Client Usage](https://docs.powersync.com/sync/streams/client-usage.md#react-hooks)                                        |

## Advanced Topics

Reference these when the standard patterns don't cover your use case:

| Topic | When to use |
|-------|-------------|
| [Client ID](https://docs.powersync.com/sync/advanced/client-id.md) | Filter or scope data by which specific client device is syncing |
| [Sync Data by Time](https://docs.powersync.com/sync/advanced/sync-data-by-time.md) | Limit sync to a rolling time window (e.g. last 30 days) |
| [Schemas and Connections](https://docs.powersync.com/sync/advanced/schemas-and-connections.md) | Use non-public Postgres schemas; wildcard schemas (`"tenant_%"`) for schema-per-tenant databases (Service v1.24.0+); HA/replica connections |
| [Multiple Client Versions](https://docs.powersync.com/sync/advanced/multiple-client-versions.md) | Support different schema versions across app releases |
| [Partitioned Tables](https://docs.powersync.com/sync/advanced/partitioned-tables.md) | Sync from Postgres partitioned tables; in Sync Streams, use `table_alias.table_suffix()` to filter on the matched suffix (not `_table_suffix`, which is Sync Rules only) |
| [Sharded Databases](https://docs.powersync.com/sync/advanced/sharded-databases.md) | Source data from multiple database shards |
| [Compatibility Flags](https://docs.powersync.com/sync/advanced/compatibility) | Fix known SQL expression edge cases in Sync Streams; if `NOT NULL`, `substr()`, or `length()` behave unexpectedly, `unstable_sqlite_expression_engine` (Service ≥ 1.22.0, experimental — may be removed) routes evaluation through actual SQLite |

### Multiple Client Versions

When a schema change breaks older app versions still in use (for example, renaming or restructuring a table), define separate stream versions so each client receives the schema it expects.

If the affected stream is manually subscribed (no `auto_subscribe: true`), prefer versioning by stream name. Define a new stream alongside the old one. New app versions subscribe to the new stream by name; older versions continue subscribing to the old stream. Remove the old stream once those versions are no longer in use.

```yaml
streams:
  # Old stream, kept for backward compatibility.
  # Remove once older app versions are no longer in use.
  user_assets:
    query: SELECT * FROM assets WHERE user_id = auth.user_id()

  # New app versions subscribe to this stream.
  # The alias maps the source table to the new client-side name.
  user_assets_v2:
    query: SELECT * FROM assets AS assets_v2 WHERE user_id = auth.user_id()
```

```js
// New app versions subscribe to the new stream
const subscription = await db.syncStream('user_assets_v2').subscribe();
```

If the stream uses `auto_subscribe: true`, clients cannot choose a stream by name. Use connection parameters instead: each client passes its version on connect, and stream queries filter on it.

```yaml
streams:
  user_assets:
    auto_subscribe: true
    query: SELECT * FROM assets
           WHERE user_id = auth.user_id()
             AND connection.parameter('schema_version') = '1'

  user_assets_v2:
    auto_subscribe: true
    query: SELECT * FROM assets AS assets_v2
           WHERE user_id = auth.user_id()
             AND connection.parameter('schema_version') = '2'
```

See [Multiple Client Versions](https://docs.powersync.com/sync/advanced/multiple-client-versions.md) for full details including the legacy Sync Rules approach.

## Convex-Specific Patterns

If the source database is Convex, apply these adjustments when writing Sync Streams:

- **ID mapping:** Use `uuid AS id` instead of `_id AS id`. Convex generates `_id` server-side; clients need a stable local UUID before writes are uploaded. Use a client-generated UUID column as `id` and a `<table>_uuid` column for relationship joins rather than the Convex `_id` foreign key.
- **Int64 casting:** Convex `Int64` values arrive as base-10 strings (`text` in SQLite). Cast to a SQLite integer when needed: `CAST(an_int64_column AS INTEGER) AS an_int64_column`.
- **Convex Auth user ID extraction:** If using Convex Auth JWTs, the `sub` claim has the format `[32-character user ID]|[session ID]`. Extract just the user ID with `substring(auth.user_id(), 1, 32)`.
- **Table names:** Do not qualify Convex table names with a schema prefix. If a qualifier is required, use the default `convex` schema.

Example applying all of the above:

```yaml
config:
  edition: 3

streams:
  user_data:
    with:
      user_lists: |
        SELECT uuid FROM lists
        WHERE owner_id = substring(auth.user_id(), 1, 32)
    auto_subscribe: true
    queries:
      - SELECT uuid AS id, name, owner_id FROM lists WHERE uuid IN user_lists
      - |
        SELECT
          uuid AS id,
          list_uuid,
          description,
          CAST(an_int64_column AS INTEGER) AS an_int64_column
        FROM todos WHERE list_uuid IN user_lists
```

# Sync Rules (Legacy, use Sync Streams for new applications)

Sync rules define how data is partitioned into buckets and distributed to clients. This is considered legacy, however will still be supported. For the best experience use [sync-streams](#sync-streams).

## Structure

```yaml
bucket_definitions:
  <bucket_name>:
    parameters: SELECT ...   # Which buckets user can access
    data:                    # What data goes in each bucket
      - SELECT ... WHERE column = bucket.parameter
```

## Parameter Queries

Determine bucket access for authenticated users:

```yaml
# User's own data
parameters: SELECT request.user_id() AS user_id

# From database table
parameters: SELECT org_id FROM users WHERE id = request.user_id()

# From JWT claims
parameters: SELECT request.jwt() ->> 'tenant_id' AS tenant_id

# From client parameters
parameters: SELECT request.parameters() ->> 'workspace_id' AS workspace_id
```

## Data Queries

Define what rows go into each bucket:

```yaml
data:
  # Basic - all columns
  - SELECT * FROM documents WHERE user_id = bucket.user_id

  # Column selection
  - SELECT id, name, created_at FROM projects WHERE org_id = bucket.org_id

  # Transformations
  - SELECT id, UPPER(status) as status FROM tasks WHERE team_id = bucket.team_id
```

## Supported SQL Features

### Functions

| Category | Functions |
|----------|-----------|
| String | `upper()`, `lower()`, `substring()`, `length()`, `hex()`, `base64()` |
| JSON | `json_extract()`, `->`, `->>`, `json_array_length()`, `json_valid()` |
| Type | `typeof()`, `cast()` |
| Utility | `ifnull()`, `iif()`, `uuid_blob()` |
| Date/Time | `unixepoch()`, `datetime()` |
| Geospatial | `st_asgeojson()`, `st_astext()`, `st_x()`, `st_y()` |

### Operators (non-parameter comparisons)

- Comparison: `=`, `!=`, `<`, `>`, `<=`, `>=`
- Logical: `AND`, `OR`, `NOT`, `IS`, `IS NOT`
- Arithmetic: `+`, `-`, `*`, `/`, `%`
- String: `||` (concatenation)
- Null: `IS NULL`, `IS NOT NULL`

### Parameter Comparisons (bucket.* or token_parameters.*)

Only `=` and `IN` supported:
```yaml
# Allowed
WHERE user_id = bucket.user_id
WHERE bucket.role IN roles_array

# NOT allowed
WHERE user_id > bucket.user_id
WHERE upper(bucket.name) = column
```

## Not Supported

- JOINs (in data queries)
- GROUP BY, HAVING
- ORDER BY, LIMIT, OFFSET, DISTINCT
- Subqueries, CTEs
- Window functions
- `COALESCE()` - use `ifnull()` instead

## Common Patterns

### Personal Data

```yaml
bucket_definitions:
  my_data:
    parameters: SELECT request.user_id() AS user_id
    data:
      - SELECT * FROM notes WHERE owner_id = bucket.user_id
      - SELECT * FROM settings WHERE user_id = bucket.user_id
```

### Team/Organization

```yaml
bucket_definitions:
  team_data:
    parameters: |
      SELECT team_id FROM team_members
      WHERE user_id = request.user_id()
    data:
      - SELECT * FROM projects WHERE team_id = bucket.team_id
      - SELECT * FROM tasks WHERE team_id = bucket.team_id
```

### Role-Based Access

```yaml
bucket_definitions:
  admin_data:
    parameters: |
      SELECT 1 AS is_admin FROM users
      WHERE id = request.user_id() AND role = 'admin'
    data:
      - SELECT * FROM audit_logs WHERE bucket.is_admin = 1
```

### Global Data (all users)

```yaml
bucket_definitions:
  global:
    parameters: SELECT 'global' AS scope
    data:
      - SELECT * FROM app_config WHERE bucket.scope = 'global'
```

### Multi-Tenant Organization

```yaml
bucket_definitions:
  org_data:
    parameters: |
      SELECT org_id
      FROM users
      WHERE id = request.user_id()
    data:
      - SELECT * FROM documents WHERE org_id = bucket.org_id
      - SELECT * FROM folders WHERE org_id = bucket.org_id

  # User's private data within org
  private_data:
    parameters: |
      SELECT org_id, request.user_id() AS user_id
      FROM users
      WHERE id = request.user_id()
    data:
      - SELECT * FROM drafts WHERE org_id = bucket.org_id AND author_id = bucket.user_id
```

### JWT Claims

```yaml
bucket_definitions:
  tenant_data:
    parameters: |
      SELECT request.jwt() ->> 'tenant_id' AS tenant_id
    data:
      - SELECT * FROM records WHERE tenant_id = bucket.tenant_id
```

### Multiple Client Versions

When a schema change affects a manually subscribed stream, define a new versioned stream alongside the old one. New app versions subscribe to the new stream by name; old versions continue with the old stream until they update.

If the stream uses `auto_subscribe: true`, clients cannot choose by name. Use connection parameters filtered per stream instead, so each app version receives the variant matching its declared version.
