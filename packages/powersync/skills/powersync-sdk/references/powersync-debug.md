---
name: powersync-debug
description: PowerSync debugging and troubleshooting — sync status, JWT verification, PSYNC error codes, replication lag, and diagnostics tools
metadata:
  tags: debugging, troubleshooting, sync-status, jwt, psync-errors, replication-lag, ps-crud, diagnostics
---

# PowerSync Debug

> **Load this when** troubleshooting sync issues, stuck "Syncing..." states, JWT errors, or replication problems.

These are debugging steps most frequently recommended by PowerSync, with an explanation of what problem each step helps identify and why it works.

Make sure to understand the [PowerSync Architecture](references/powersync-overview.md) before debugging.

## First Response When the UI Is Stuck on `Syncing...`

Before asking for console logs or editing app code, verify these in order:

1. The PowerSync endpoint URL returned by `fetchCredentials()` is correct (not the backend URL).
2. The PowerSync service has a valid source DB connection.
3. Sync config was deployed and starts with `config: edition: 3`.
4. Client auth is configured correctly (Supabase auth, custom JWKS, or other provider).
5. Source database replication/publication/CDC is set up for the synced tables.

Only inspect frontend connector code or SDK state after all five checks pass.

Before requesting browser console logs, ask the operator to confirm:

- the instance exists
- the DB connection was configured
- sync config was deployed
- client auth was configured
- source database replication/publication/CDC was set up

## Check `SyncStatus` / `currentStatus` Before Investigating Further

What it identifies: Whether the SDK is actually connected, syncing, or has hit an error, before diving into logs.

Why: `SyncStatus` is the SDK's live view of its own state. It surfaces connection state, whether a first sync has completed, whether uploads are processing etc. Checking it first avoids chasing a perceived bug that is actually just "not yet connected."

How:

Each of the PowerSync Client SDKs have the SyncStatus class that can be used to access the client sync status.

| SDK             | Link                                                                                                                                                                                                |
|-----------------|-----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| Flutter         | [SyncStatus Class](https://pub.dev/documentation/powersync/latest/powersync/SyncStatus-class.html)                                                                                                  |
| Kotlin          | [SyncStatus Class](https://powersync-ja.github.io/powersync-kotlin/core/com.powersync.sync/-sync-status/index.html?query=data%20class%20SyncStatus%20:%20SyncStatusData)                            |
| Swift           | [SyncStatusData](https://powersync-ja.github.io/powersync-swift/documentation/powersync/syncstatusdata)                                                                                            |
| Web             | [SyncStatus Class](https://powersync-ja.github.io/powersync-js/web-sdk/classes/SyncStatus)                                                                                                          |
| React Native    | [SyncStatus Class](https://powersync-ja.github.io/powersync-js/react-native-sdk/classes/SyncStatus)                                                                                                |
| Node.js         | [SyncStatus Class](https://powersync-ja.github.io/powersync-js/node-sdk/classes/SyncStatus)                                                                                                         |
| .NET (Alpha)    | [SyncStatus.cs](https://github.com/powersync-ja/powersync-dotnet/blob/main/PowerSync/PowerSync.Common/DB/Crud/SyncStatus.cs)                                   |

Key fields to check: `connected`, `downloading`, `uploading`, `lastSyncedAt`, `hasSynced`, `downloadError`, `uploadError`.

## Read Sync Errors That Print as `[object Object]` (Web)

What it identifies: The actual name, message, and cause of a sync error that a web app logs as `[object Object]`.

Why: On the Web SDK, errors raised inside the shared sync worker cross the MessagePort serialized by `SyncStatus.toJSON()` and arrive as plain `{name, message, stack, cause}` objects. They are not `Error` instances: `String(error)` prints `[object Object]` and `instanceof Error` is false, so generic error formatting hides the real failure.

How: Read the `name` and `message` fields directly, and flatten the `cause` chain (each `cause` can itself be a serialized error). Always record which side reported the failure: `status.uploadError` or `status.downloadError`.

What to look for: The two sides call for different first responses. `uploadError` points at the upload queue and your backend (see [Inspect `ps_crud` Directly](#inspect-ps_crud-directly)); `downloadError` points at credentials, the service, or the download path.

## A Resolved `connect()` Is Not a Working Connection

What it identifies: Why an app stays stuck on `Syncing...` even though `connect()` returned without throwing.

Why: `connect()` is fire-and-forget. It resolves even when `fetchCredentials()` fails, and the retry loop that follows surfaces only through `SyncStatus`: `downloadError` is set and `connected` stays `false` between retries.

How: Treat `SyncStatus` as the source of truth for connection health, not the `connect()` promise. Do not put `await connect()` on a UI-blocking path expecting it to fail loudly; it won't.

What to look for: `connected: false` with a populated `downloadError` after `connect()` resolved means the credential or connection loop is failing silently. Start with `fetchCredentials()` and the endpoint URL.

## Persisted Sync State Is Available at Open, Offline

What it identifies: Whether first-sync UI showing on every reload is an app wiring bug rather than an SDK problem.

Why: `hasSynced`, `lastSyncedAt`, and per-stream subscription state are read from the local database when it opens (via `powersync_offline_sync_status()`), before any network activity. A device that has synced before reports ready milliseconds after open, even offline.

How: If an app shows first-sync UI on every reload, inspect what the UI gates on. The SDK's persisted state is correct; the app is likely gating on a value that resets per session (a fresh in-memory flag, or live connection state) instead of `hasSynced`.

## Never Gate Local-Only Reads on Stream Readiness

What it identifies: Guest or signed-out surfaces pinned to a loading state forever.

Why: The "wait for first sync before trusting local queries" rule applies only to identities that can download. A guest or local-only database never connects, so its streams never report synced. Gating guest reads on `hasSynced` (or a `waitForStream` option) pins every guest surface to a permanent loading state.

How: Gate on whether the current identity is expected to sync, for example `mustWaitForStream = authLoaded && isSignedIn`, and apply that gate to every collection read hook.

What to look for: Partial application. A fix applied to one read hook but not the others produces surfaces that load and surfaces that spin in the same app. Audit every read hook that gates on sync readiness, not only the one that was reported.

## Enable the Request Logger (Swift SDK)

What it identifies: The exact HTTP request being made to the PowerSync Service to inspect the URL, method, headers, authorization token, and response status code. Use this when authentication failures, JWT errors, or endpoint misconfigurations need to be diagnosed on iOS/macOS.

Why: The Rust-based sync client doesn't log request details by default. Adding a `SyncRequestLoggerConfiguration` gives a full audit trail of every sync stream request — `endpoint` URL, JWT, response status, and error bodies (including `PSYNC_S2101` JWT key-id mismatches).

How:
```swift
try await db.connect(
    connector: connector,
    options: ConnectOptions(
        clientConfiguration: SyncClientConfiguration(
            requestLogger: SyncRequestLoggerConfiguration(
                requestLevel: .headers
            ) { message in
                print("[SyncRequest] \(message)")
            }
        )
    )
)
```

Look for: The `Authorization: Token <jwt>` header and the response status (`200`, `401`, `404`). A `401` with `PSYNC_S2101` in the response body means JWT key ID mismatch.

## Use the Sync Diagnostics Client

What it identifies: Whether the PowerSync Service is processing your sync rules correctly, what data is in each bucket for a given user, and whether parameter queries are resolving as expected.

Why: Most "data not showing up on the client" issues are actually server-side: wrong Sync Rules / Sync Streams, parameter query not matching etc. The Diagnostics Client lets you verify this without touching client code. It runs entirely in the browser against your real instance.

How: Go to [diagnostics-app.powersync.com](https://diagnostics-app.powersync.com/), connect to your PowerSync instance, and:
1. Check the Client Parameters page to configure client parameters to test buckets that use parameter queries.
2. Run queries directly in the SQL Console to confirm row counts.
3. Check bucket and Sync Streams subscriptions contents to see exactly what data will be synced to a given user.
4. Use the SQLite File Inspector to drag-and-drop a local `.db` file and inspect its contents directly in the browser.

The Sync Diagnostics Client is also self-hostable and the Docker image is available on [Docker hub](https://hub.docker.com/r/journeyapps/powersync-diagnostics-app).


## Inspect `ps_crud` Directly

What it identifies: Whether local writes are reaching the upload queue, how many are pending, and what operation/data they contain.

Why: `ps_crud` is the raw upload queue table in the local SQLite database. It is the ground truth for "has this write been recorded by PowerSync?". This is distinct from whether it has been uploaded to the backend. If `ps_crud` is empty after a write, the write either didn't go through the PowerSync managed table, or `transaction.complete()` was called prematurely.

How:
```sqlite
SELECT * FROM ps_crud ORDER BY id
```

What to look for: `op` (PUT/PATCH/DELETE), `type` (table name), `id`, `opData` (changed columns). If a column you updated is missing from `opData`, it means its value didn't change from the previous row (PowerSync intentionally omits unchanged values).

## A Wedged Upload Looks Like Syncing Forever

What it identifies: A first sync that never completes because a failing upload is blocking downloads, presenting as an eternal spinner rather than an upload error.

Why: Uploads are processed before downloads. One upload that keeps failing blocks checkpoint application, so the first sync never completes. The UI symptom is an indefinite `Syncing...` state; nothing on screen mentions uploads.

How: Inspect `ps_crud` (see the preceding section) for stuck entries, then check `status.uploadError` for the failure.

What to look for: A non-empty `ps_crud` whose oldest entry never drains, together with a latched `uploadError`. In the app's own UX, after a grace window, distinguish "downloading" (connected, download progress advancing) from "stalled" (disconnected, or a latched `uploadError`/`downloadError`) instead of showing an indefinite optimistic spinner; the optimistic spinner hides exactly this failure.

## Log the Actual `endpoint` URL in `fetchCredentials()`

What it identifies: Whether the `endpoint` value returned by your connector is pointing at the PowerSync Service, not your app backend.

Why: The most common cause of `404 Not Found` on `/write-checkpoint2.json` and `/sync/stream` is passing the wrong URL as `endpoint`. PowerSync builds its own request URLs by appending paths to whatever `endpoint` returns, if that's your app backend, every internal PowerSync request 404s. Adding a log statement catches this immediately.

How: Adding a log statement or set breakpoints to catch the endpoint before fetchCredentials() returns.

## Run `EXPLAIN QUERY PLAN` for Slow Queries

What it identifies: Full table scans, missing indexes, and inefficient joins in client-side SQLite queries.

Why: PowerSync's default JSON-based views extract column values on every row scan, which compounds in joins. Without indexes on join columns, SQLite performs a full scan of every row. `EXPLAIN QUERY PLAN` makes this visible. A `SCAN TABLE` without `USING INDEX` is a red flag.

How:
```sqlite
EXPLAIN QUERY PLAN SELECT ...
```

What to look for: `SCAN TABLE <name>` (bad / no index used) vs. `SEARCH TABLE <name> USING INDEX` (good). If your PowerSync tables show a SCAN, switch to [raw tables](https://docs.powersync.com/usage/use-case-examples/raw-tables.md). If your non-PowerSync tables show a SCAN, add an index on the join column.

## Benchmark Client Queries Without a Device

What it identifies: Missing or unusable schema indexes and expensive query shapes, before they ship, using any local SQLite instead of a real device.

Why: The client storage layout is reproducible. Each PowerSync table is stored as `ps_data__<table>(id, data)` with a view exposing `CAST(json_extract(data, '$.col') AS <type>)` columns, and schema indexes compile to those same expressions. A benchmark database built with this layout exercises the same query plans as a real client.

How: Seed 10k-50k rows into an in-memory SQLite database using that layout, run the app's real query builders against it, and read `EXPLAIN QUERY PLAN` for each query.

What to look for:

- `SCAN` plus `USE TEMP B-TREE FOR ORDER BY` is the red flag; a matching composite index turns it into `SEARCH ... USING INDEX`.
- A filter wrapped in an expression (`CASE`, or `coalesce()` around the indexed column) can never use a schema index. Rewrite predicates as bare-column equalities so they are sargable, and let the planner choose the index.
- The planner's index-versus-scan choice depends on data distribution (after `ANALYZE`). Seed the benchmark with realistic skew, or the conclusion is wrong.

## Check Package Versions and Duplicate Dependencies

What it identifies: Version mismatches between PowerSync packages and their peers (Drizzle, TanStack, op-sqlite), or duplicate transitive dependencies causing type conflicts.

Why: TypeScript errors with `@tanstack/react-db` and `@powersync/drizzle-driver` are often caused by multiple versions of `@powersync/common` or `@tanstack/db` installed across direct and transitive dependencies. The packages reference internal types that clash when versions differ.

How:
```bash
# Check for multiple PowerSync common versions
npm ls @powersync/common

# Check TanStack version alignment
npm ls @tanstack/react-db @tanstack/powersync-db-collection @tanstack/db

# Check op-sqlite peer dependency
npm ls @powersync/op-sqlite
```

Also try: Deleting `node_modules` and the lock file, then reinstalling — stale cached resolutions can cause phantom mismatches.

## Verify JWT Claims

What it identifies: Whether your JWT contains the expected `sub`, `aud`, `iss`, `exp`, `kid`, and custom claims that PowerSync uses for auth and parameter queries.

Why: JWT issues are the most common connection failure cause. The PowerSync Service validates the `kid` (key ID) against its configured keystore. A mismatch gives `PSYNC_S2101` (See [Error Codes Reference](https://docs.powersync.com/debugging/error-codes.md#error-codes-reference)). It also enforces `exp` ≤ 86400s (`PSYNC_S2104`). Custom claims used in parameter queries (e.g. `app_metadata`) must be present and structured exactly as the sync rules expect.

How: Paste your JWT into [jwt.io](https://jwt.io) or decode it in your debugger.

Check:
- `sub` — user ID used in `request.user_id()`
- `kid` — must match a key in PowerSync's keystore (Supabase: legacy vs. JWKS)
- `exp` — must be ≤ `iat + 86400`
- `aud` — must match your configured audience
- Custom claims e.g. `app_metadata.my_field` must use `$.app_metadata.my_field` in sync rules

The Sync Diagnostics Client also decodes and displays the active JWT automatically.

## Call `disconnectAndClear()` When Data Looks Wrong After User Switch

What it identifies: Whether stale data from a previous user is polluting the local SQLite database.

Why: `disconnect()` closes the sync connection but keeps all local data. If you call `disconnect()` on logout and then `connect()` with a new user, the new user's UI will initially display the old user's data until sync completes. `disconnectAndClear()` wipes the local database first, so the new user starts from a clean state.

When to use each:
- `disconnect()` — temporary offline, token refresh, app backgrounding. Safe to reconnect as the same user.
- `disconnectAndClear()` — user logout, user account switch. Required to prevent data leakage between users.

## PSYNC Error Codes

PowerSync has a documented list of error codes with corresponding descriptions. 

These error codes are prefixed with `PSYNC_`, indicating a specific PowerSync related error.

Use them to help drill into specific errors to help debug an issue.

Key codes to recognize at runtime:

| Code | Condition | Action |
|------|-----------|--------|
| `PSYNC_S1005` | Storage version not supported | Caused by a service downgrade; upgrade the PowerSync Service to match the stored version |
| `PSYNC_S1146` | Replication slot invalidated (`wal_status = 'lost'`) | Use the recovery steps in [Replication Lag Debugging (Postgres)](#replication-lag-debugging-postgres) |
| `PSYNC_S1601` | MSSQL: CDC capture instance dropped during polling | Re-enable CDC for the affected table; replication resumes automatically once CDC is active |
| `PSYNC_S2305` | Too many buckets or too many parameter query results | Read the error message: `Too many buckets` means reduce unique bucket count; `Too many parameter query results` means reduce parameter lookup rows. See [Reducing Bucket Count](https://docs.powersync.com/sync/advanced/reducing-bucket-count). |

See [Error Codes Reference](https://docs.powersync.com/debugging/error-codes.md#error-codes-reference) for more information.

## Diagnosing Sync Latency

What it identifies: Which stage of the downstream pipeline is slow — source database to PowerSync Service (replication), or PowerSync Service to client (sync session).

Why: There is no single trace covering the full path. The upstream path (client write → backend API → source database) sits outside PowerSync; instrument your backend API directly for that leg. The downstream pipeline must be isolated per stage.

### Measuring End-to-End Downstream Latency

Put a timestamp in the data. When a row is written or updated in the source database, set a column to the current server time (e.g. `updated_at = NOW()`). On the client, compare that timestamp to the time the row appears in the local database. The difference measures source-commit to device-visible latency across both downstream stages combined.

### Stage 1: Source Database to PowerSync Service

Check the **Replication Lag** chart in the **Metrics** view of the [PowerSync Dashboard](https://dashboard.powersync.com/). Replicator logs in the **Logs** view surface errors that cause delays at this stage.

When the user shares instance logs from the **Logs** view, look for `Flushed` entries. Each entry records one batch written to bucket storage and is the most direct view of replication throughput:

```
Flushed: 1200 ops, 30 index entries, 450 records. 512kb in 240ms. Last op_id: 88421. Replication lag: 3s
```

Structured log properties are available under `flushed` on each entry:

| Property | What it measures |
|----------|------------------|
| `bucket_ops_count` | Operations appended to bucket operation history. One source row produces one operation per bucket it belongs to; rows shared across many buckets produce many operations. |
| `parameter_indexes_count` | Parameter index entries written for rows feeding stream parameters. |
| `source_records_count` | Source rows persisted with their bucket and lookup memberships. |
| `size` | Flush size in bytes. |
| `duration` | Write time in milliseconds. |
| `replication_lag_seconds` | Age of the oldest uncommitted change in this batch, in seconds. Only present when the Service can determine this value. |

For source-specific guidance (Postgres, MongoDB, MySQL, SQL Server) see [Replication Lag](https://docs.powersync.com/maintenance-ops/replication-lag) and [Replication Lag Debugging (Postgres)](#replication-lag-debugging-postgres) below.

### Stage 2: PowerSync Service to Client

Sync & API logs record two events per sync session:

- **Sync stream started** — logged when the client connects. Fields: `user_id`, `client_id`, `app_metadata` (if set), `client_params`, `user_agent`, `rid` (request ID).
- **Sync stream complete** — logged when the session ends. Fields: `user_id`, `client_id`, `app_metadata` (if set), `operations_synced`, `operation_counts` (`put`, `remove`, `move`, `clear`), `data_synced_bytes`, `data_sent_bytes`, `stream_ms` (session duration), `close_reason`, `rid`.

Both events share the same `rid`; to match a started/complete pair for a single session, search `rid:<request-id>` in the dashboard **Logs** view. To find a specific user's sessions, search `user_id:<user-id>`. If a known error is producing noise, prefix the filter with `-` to exclude matching entries. For example, `-error:PSYNC_S2106` hides all entries with that error code.

[Custom metadata](https://docs.powersync.com/maintenance-ops/monitoring-and-alerting#custom-metadata-in-sync-logs) set at `connect()` time appears in both events, enabling filtering by app version, environment, or other context.

### Common Causes

- **Large initial sync** — sync rules with a large dataset will slow the first sync after connecting. Inspect bucket sizes with the [Sync Diagnostics Client](https://diagnostics-app.powersync.com/).
- **Upload queue blocking downloads** — by default, uploads are processed before downloads. Buckets and streams at [priority 0](https://docs.powersync.com/sync/advanced/prioritized-sync) are not blocked by uploads but carry trade-offs around sync consistency.
- **Replication lag on the source database** — high write volume, long-running transactions, bulk updates, or backfills can cause replication to fall behind. See Stage 1 above.
- **Too many buckets or parameter results per user**: two per-user limits apply, both defaulting to 1,000. Exceeding either fails sync with `PSYNC_S2305`. High bucket counts also increase incremental sync overhead roughly linearly. See [Reducing Bucket Count](https://docs.powersync.com/sync/advanced/reducing-bucket-count).

# Replication Lag Debugging (Postgres)

What it identifies:
- Sync rules deployment stuck in "processing" for many hours or days (e.g. 24–48+ hours)
- PowerSync logs or dashboard surface error `PSYNC_S1146`: `Replication slot powersync_1_xxxx was invalidated (reason: wal_removed). Increase max_slot_wal_keep_size on the source database and delete the existing slot to recover.`
- Slot version numbers keep increasing (e.g. _27_, _28_, _30_) as reprocessing restarts
- Storage usage spikes during reprocessing (expected, but can trigger limit alerts)
- Source DB is Supabase or another Postgres with default max_slot_wal_keep_size (often 4 GB)
- On self-hosted instances: `wal_status = 'lost'` in the Diagnostics API, or a WAL budget warning when `safe_wal_size` drops below 50% of `max_slot_wal_keep_size`

Why:
- `max_slot_wal_keep_size` limits how much WAL Postgres keeps for replication slots
- During initial replication, WAL grows quickly because: (1) full snapshot of all tables in sync rules, (2) ongoing writes on the source DB
- If replication lag exceeds `max_slot_wal_keep_size`, Postgres invalidates the slot (`wal_status = 'lost'`)
- PowerSync detects the invalid slot, creates a new one, and restarts reprocessing
- With the same limit, the new slot is invalidated again, causing a loop
- Supabase's default 4 GB is often too small for large datasets (e.g. 9+ hour initial replication)

How:
Confirm the cause — check `wal_status` and the configured WAL cap on the source database:

```sql
SHOW max_slot_wal_keep_size;

SELECT slot_name, wal_status, safe_wal_size
FROM pg_replication_slots;
```

If `wal_status` is `'lost'` (error `PSYNC_S1146`), follow these steps to recover:

1. Increase `max_slot_wal_keep_size` on the source Postgres database. See [Managing and Monitoring Replication Lag](https://docs.powersync.com/maintenance-ops/production-readiness-guide#managing-and-monitoring-replication-lag) for sizing guidance.
2. Drop the invalidated slot (replace `powersync_1_xxxx` with the actual slot name from the error message):
```sql
SELECT pg_drop_replication_slot('powersync_1_xxxx');
```
3. Restart the PowerSync Service. It creates a new slot and restarts replication from scratch.

If the slot was invalidated before the initial snapshot completed, PowerSync will not auto-retry — drop the slot manually before the service can recover.

If the invalidation reason is `idle_timeout` (Postgres 18+ only), the slot was invalidated due to inactivity rather than WAL growth. In that case, increase `idle_replication_slot_timeout` on the source database instead of `max_slot_wal_keep_size`.

For proactive monitoring: PowerSync emits a WAL budget warning in the dashboard, Diagnostics API, and service logs when `safe_wal_size` drops below 50% of `max_slot_wal_keep_size`. Increase `max_slot_wal_keep_size` before the budget is exhausted and the slot is invalidated.

## Diagnostics API: WAL Health Fields (Self-Hosted)

When a self-hosted operator reports replication or WAL issues, check these fields in the Diagnostics API response (`POST /api/admin/v1/diagnostics`). Retrieve with the CLI: `powersync status --output=json | jq '.data.active_sync_rules'`

Each entry in `active_sync_rules.connections[]` includes:

| Field | What to look for |
|-------|------------------|
| `wal_status` | `'reserved'` or `'extended'` is healthy; `'lost'` means the slot is invalidated — use the recovery steps above |
| `safe_wal_size` | Remaining WAL budget in bytes; if below 50% of `max_slot_wal_keep_size`, increase the limit proactively |
| `max_slot_wal_keep_size` | Configured WAL cap on the source database |
| `initial_replication_done` | If `false` during a long deployment, the initial snapshot is still in progress |
| `replication_lag_bytes` | Current lag; sustained high lag increases invalidation risk |

Warnings and errors appear in `active_sync_rules.errors[]`:
- WAL budget warning when `safe_wal_size` < 50% of `max_slot_wal_keep_size`
- Replication lag warning when no replicated commit received in > 5 minutes (warning) or > 15 minutes (fatal)
- `PSYNC_S1146` when `wal_status = 'lost'`

If a new sync config is currently deploying, check `deploying_sync_rules.connections[]` and `deploying_sync_rules.errors[]` — the same fields apply. PowerSync continues serving clients from `active_sync_rules` while `deploying_sync_rules` completes its initial snapshot.
