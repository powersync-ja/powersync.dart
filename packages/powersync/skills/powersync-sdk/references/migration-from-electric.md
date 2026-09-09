---
name: migration-from-electric
description: Conceptual mapping and migration steps for teams moving from Electric Cloud to PowerSync
metadata:
  tags: electric, migration, electric-shapes, sync-streams, postgres, jwt, upload-queue, disconnectAndClear
---

# Migrating from Electric Cloud to PowerSync

> **Load this when** the user mentions Electric Cloud, Electric Shapes, or migrating from Electric to PowerSync.

Electric Cloud is shutting down. This file covers what an agent needs to help users migrate to PowerSync.

## Key Architecture Difference

Electric Shapes are defined client-side, per request. PowerSync Sync Streams are declared server-side in YAML; clients subscribe by name and supply parameters at runtime.

Shape-to-Sync-Stream migration is not 1-for-1. Re-designing the sync layer is expected.

## Comparison

| Dimension | Electric (Shapes) | PowerSync (Sync Streams) |
|-----------|-------------------|--------------------------|
| Definition | Client-side, per-request. Each `table` + optional `where`/`columns` set is a distinct Shape. | Server-side YAML. Clients subscribe by stream name and supply parameters at runtime. `auto_subscribe: true` starts a stream on connect. |
| Relational scope | Single table only. | JOIN supported; one stream can carry multiple queries. |
| Authorization | Backend validates Shape requests before serving them. | Sync Stream queries enforce access using signed JWT claims. Client-supplied `subscription.parameter()` values are untrusted; always pair them with an `auth.user_id()` guard. |
| Client store | In-memory by default; persistence requires a separate integration (PGlite, TanStack DB). | SQLite with a declared AppSchema. The Web SDK uses persistent IndexedDB by default. |
| Local queries | `useShape`, `shape.rows`, TanStack DB live queries. | SQL against SQLite (`useQuery`, `watch()`); also supports TanStack DB and ORMs like Drizzle. |
| Writes | Read-path only; app writes directly to its backend. | FIFO upload queue via `uploadData()`. Bypassing the queue causes data flickering when the sync response arrives. |
| Primary key | Must include Postgres primary key columns. | Each synced table requires a single text `id` column. Alias or cast the source column if it has a different name or type. The `id` column is added automatically; do not define it in the client schema. |

## Postgres Setup

When configuring the source database:

- Do not reuse the Electric publication. PowerSync requires a publication named `powersync`.
- Use `BYPASSRLS` for the PowerSync role. Authorization is enforced in Sync Stream queries, not at the database row level.

See `references/onboarding-custom.md` for the full Postgres setup sequence and `references/sync-config.md` for Sync Streams YAML reference.

## Shape to Sync Stream Mapping

An Electric Shape that syncs a user's projects:

```typescript
// Electric: client-side, filter expressed as a raw WHERE string
const { data } = useShape({
  url: `http://localhost:3000/v1/shape`,
  params: {
    table: `projects`,
    where: `owner_id = '${userId}'`,
  },
})
```

The equivalent Sync Stream in `sync-config.yaml`:

```yaml
config:
  edition: 3

streams:
  my_projects:
    auto_subscribe: true
    query: SELECT * FROM projects WHERE owner_id = auth.user_id()
```

For on-demand streams with a client-supplied parameter, add an auth guard that limits the parameter to rows the user owns:

```yaml
streams:
  project_tasks:
    accept_potentially_dangerous_queries: true
    query: |
      SELECT * FROM tasks
      WHERE project_id = subscription.parameter('project_id')
        AND project_id IN (SELECT id FROM projects WHERE owner_id = auth.user_id())
```

## Authorization Model

Electric routes Shape requests through a backend to authorize them. PowerSync embeds authorization in Sync Stream queries.

- Use `auth.user_id()` to filter by the authenticated user's JWT subject.
- Use `auth.jwt() ->> 'claim_name'` for custom claims (tenant IDs, roles).
- When using `subscription.parameter()`, always add an `auth.user_id()` condition that limits which parameter values produce rows. A client can supply any value; the auth guard is what makes the query safe.

## Frontend Migration (Web JS/TS)

1. Install: `pnpm install @powersync/web`
2. Generate the client schema from the Dashboard or CLI. The `id` column is added automatically; do not define it.
3. Instantiate `PowerSyncDatabase` with the schema and a `dbFilename`.
4. Implement `PowerSyncBackendConnector`:
   - `fetchCredentials()` returns the JWT and the PowerSync Cloud endpoint.
   - `uploadData()` sends local mutations to your backend API.
5. Replace `useShape` with `useQuery` or `watch()` for live SQL queries.
6. Replace Shape handle/offset usage with `waitForFirstSync()` and Sync Stream status checks.
7. Tie on-demand Sync Stream subscriptions to component or route lifetime. The PowerSync React hooks handle automatic subscribe and unsubscribe.

For other SDKs (Dart, Kotlin, Swift, .NET, Rust), load the relevant SDK reference file.

## Subscription TTL

Each Sync Stream subscription caches data in SQLite after unsubscribing. Default TTL is 24 hours.

- If reducing local disk usage matters: use a shorter TTL.
- If fast page reload performance matters: use a longer TTL or `Infinity`.

## Write Path

Electric apps write directly to the backend. PowerSync introduces an upload queue.

- Local INSERT, UPDATE, and DELETE operations enter a FIFO queue and are sent to your backend via `uploadData()`.
- If code writes directly to the backend and bypasses the queue, data flickering occurs when the sync response arrives from the server.
- Call `disconnectAndClear()` on logout or user switch only after the upload queue is empty. Clearing while uploads are pending discards those mutations.

See `references/custom-backend.md` for the `uploadData` contract and error-handling rules.
