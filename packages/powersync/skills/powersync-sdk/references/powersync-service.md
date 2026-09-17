---
name: powersync-service
description: PowerSync Service configuration — self-hosting, Docker, Kubernetes, Helm, source database setup, bucket storage, authentication, and PowerSync Cloud
metadata:
  tags: service, self-hosted, docker, postgresql, mongodb, documentdb, cosmosdb, mysql, mssql, convex, authentication, jwt, replication, configuration, private-endpoints, privatelink, vpc, aws, kubernetes, helm, eks, prometheus_port, heartbeat_interval_seconds, snapshot_socket_timeout, healthcheck, migrations, disable_auto_migration, object_storage, s3, storage_version
---

# PowerSync Service

> **Load this when** configuring the PowerSync service itself — self-hosting, Docker, Kubernetes, source database connections, bucket storage, or authentication setup.

## Table of Contents
- [Sync Config](#sync-config)
- [Service Configuration (Self-hosted)](#service-configuration-self-hosted)
- [PowerSync Cloud Setup](#powersync-cloud-setup)
- [Private Endpoints](#private-endpoints)
- [Source Database Setup](#source-database-setup)
- [App Backend](#app-backend)
- [Authentication](#authentication)

Guidance for configuring PowerSync Service, sync config, and database replication.

Critical warnings for fast setup:

- Cloud and self-hosted service config both use `replication.connections`, never a root-level `connections`.
- If the app is stuck on `Syncing...`, the default diagnosis is incomplete backend setup: missing DB connection, missing sync config, missing client auth, or missing publication.

For source code see: [powersync-service](https://github.com/powersync-ja/powersync-service/)

For debugging see: [powersync-debug.md](references/powersync-debug.md).

## Sync Config

The rules that instruct the PowerSync Service what data to replicate and download to client application.

See [sync-config.md](references/sync-config.md) for detailed information.

## Service Configuration (Self-hosted)

Information on how to configure a PowerSync Service instance in a self-hosted environment. 

### Docker Image
The PowerSync Service Docker image is available on [Docker hub](https://hub.docker.com/r/journeyapps/powersync-service).

Releases are published to two channels: Stable and Next. For self-hosted, select the channel by choosing the image tag. For PowerSync Cloud, configure the channel per instance in the Dashboard under Settings.

| Channel | Example tags                         | Use for                   |
| ------- | ------------------------------------ | ------------------------- |
| Stable  | `1.23.0`, `1.23`, `1`                | Production                |
| Next    | `1.23.0-next`, `1.23-next`, `1-next` | Testing upcoming releases |

If generating a production Docker Compose or run command, use a pinned Stable tag (e.g. `1.23.0`) rather than `latest`. The `latest` tag tracks the current Stable release but can advance across major versions; treat it as development-only.

Quick Start:
```
docker run \
-p 8080:8080 \
-e POWERSYNC_CONFIG_B64="$(base64 -i ./config.yaml)" \
--network my-local-dev-network \
--name my-powersync journeyapps/powersync-service:latest
```

> **Port mapping:** The PowerSync service listens on port **8080** inside the container. Use `-p 8080:8080` (or `-p <host-port>:8080`). Do **not** use `8080:80` — the service does not listen on port 80.

### Configuration

There are four configuration methods available:
1. Base64-encoded config in the `POWERSYNC_CONFIG_B64` environment variable
2. Config file on a mounted volume (pass path with `-c` / `--config-path`)
3. Base64-encoded config as a command-line argument (`-c64`)
4. Sync config separately via `POWERSYNC_SYNC_CONFIG_B64` environment variable or `-sync64` flag

> **Sync config flag:** The Docker image does **not** accept a `-s` flag for sync config. Use the `POWERSYNC_SYNC_CONFIG_B64` environment variable or the `-sync64` command-line flag instead.

#### Docker Compose with mounted config + sync config

```yaml
powersync:
  image: journeyapps/powersync-service:latest  # For production, use a pinned tag (e.g. 1.23.0)
  ports:
    - "8080:8080"
  environment:
    PS_DATA_SOURCE_URI: "postgresql://user@host:5432/db"
    PS_STORAGE_URI: "mongodb://mongo:27017/powersync_storage"
    POWERSYNC_SYNC_CONFIG_B64: "<base64-encoded sync-config.yaml>"
  volumes:
    - ./powersync/service.yaml:/config/service.yaml
  command: ["start", "-c", "/config/service.yaml"]
```

Generate the base64 value: `base64 -i ./powersync/sync-config.yaml` (macOS) or `base64 -w0 ./powersync/sync-config.yaml` (Linux).

| Resource                        | Description                                                                                                             |
|----------------------------------|-------------------------------------------------------------------------------------------------------------------------|
| [Self-Hosted Configuration Reference](https://docs.powersync.com/configuration/powersync-service/self-hosted-instances) | Full reference for all service.yaml configuration options |
| [Config Schema](https://unpkg.com/@powersync/service-schema@1.20.0/json-schema/powersync-config.json)                | JSON schema reference for PowerSync Service config                               |
| [self-host-demo](https://github.com/powersync-ja/self-host-demo) repo                                            | Example configurations for local development                                     |

#### Environment variable substitution
Use !env PS_VARIABLE_NAME in YAML for config values.

### Complete service.yaml Example

Below is a minimal but complete `service.yaml` for a self-hosted instance. Pay close attention to the YAML nesting — in particular, the database connection **must** be under `replication.connections`, not a top-level `connections` key.

```yaml
# powersync/service.yaml — self-hosted
replication:
  connections:
    - type: postgresql
      uri: !env PS_DATA_SOURCE_URI   # e.g. postgresql://user@host:5432/db

storage:
  type: mongodb
  uri: !env PS_STORAGE_URI           # e.g. mongodb://localhost:27017/powersync

# Client auth — required before `powersync generate token` works
client_auth:
  jwks_uri: !env PS_JWKS_URI

# API key for CLI access (matches PS_ADMIN_TOKEN)
api:
  tokens:
    - !env PS_ADMIN_TOKEN
```

### Minimal Cloud service.yaml Examples

For PowerSync Cloud, the minimal shape depends on your auth provider.

**Cloud + Supabase Auth:**

```yaml
# powersync/service.yaml — Cloud with Supabase
replication:
  connections:
    - type: postgresql
      uri: !env PS_DATABASE_URI

client_auth:
  supabase: true
```

**Cloud + Custom Auth (JWKS):**

```yaml
# powersync/service.yaml — Cloud with custom JWT auth
replication:
  connections:
    - type: postgresql
      uri: !env PS_DATABASE_URI

client_auth:
  jwks_uri: !env PS_JWKS_URI
  audience:
    - !env POWERSYNC_URL
```

Choose the example that matches your auth provider. See `references/supabase-auth.md` for Supabase details or `references/custom-backend.md` for custom JWT setup.

### Additional service.yaml Options

> Load this section when configuring monitoring, operational controls, or newer connection options.

#### Telemetry and Prometheus Metrics

`telemetry` is a top-level key in `service.yaml`, not nested under `client_auth`. To expose Prometheus metrics for scraping, set `telemetry.prometheus_port`:

```yaml
telemetry:
  disable_telemetry_sharing: false
  prometheus_port: 9090
```

#### Health Check Probes

If `healthcheck.probes` is not set, the Service uses legacy default behavior. When `probes` is configured, each mechanism requires explicit opt-in:

```yaml
healthcheck:
  probes:
    use_filesystem: true  # Expose health status via filesystem files
    use_http: true        # Expose health status via HTTP endpoints
```

#### Storage Migrations

By default, the Service applies storage schema migrations on startup. To disable automatic migrations (for example, when running migrations as a separate step):

```yaml
migrations:
  disable_auto_migration: true
```

#### Connection Heartbeats

All source connection types support `heartbeat_interval_seconds` (default 60, range 5-60, available since Service v1.24.0). The Service writes periodic heartbeats to the source to keep replication active when the change stream has not advanced recently. Tune this when you see stale replication:

```yaml
replication:
  connections:
    - type: postgresql    # Also applies to mongodb, mysql, mssql
      uri: !env PS_DATA_SOURCE_URI
      heartbeat_interval_seconds: 30
```

#### Postgres: Snapshot Socket Timeout

If you see `Socket timed out` errors in Service logs during the initial Postgres snapshot, the storage database is stalling the snapshot beyond the idle socket timeout. Increase `snapshot_socket_timeout` (default 30 seconds, available since Service v1.26.0):

```yaml
replication:
  connections:
    - type: postgresql
      uri: !env PS_DATA_SOURCE_URI
      snapshot_socket_timeout: 120
```

#### MongoDB Object Storage (Experimental)

To offload large bucket data chunks to S3-compatible object storage instead of MongoDB, configure `storage.object_storage` (available since Service v1.24.0; requires `storage_version: 3` in your sync config):

```yaml
storage:
  type: mongodb
  uri: !env PS_STORAGE_URI
  object_storage:
    type: s3
    bucket: my-powersync-bucket
    region: us-east-1
    access_key_id: !env PS_S3_KEY
    secret_access_key: !env PS_S3_SECRET
```

#### Storage Version Default

To control which storage version the Service uses for new sync config deployments (available since Service v1.26.0), set `storage.default_storage_version`. Even numbers are stable; odd numbers are experimental:

```yaml
storage:
  default_storage_version: 2  # 2 (stable, default); 3 (experimental)
```

Set this before a Service downgrade, or to delay a storage format upgrade. See [Storage Version](https://docs.powersync.com/sync/advanced/compatibility#storage-version) for details.

#### Deprecated: `sync_rules` Key

The top-level `sync_rules` key is a deprecated alias for `sync_config`. Use `sync_config` in new configurations.

### Replication connections

**IMPORTANT:** The database connection **must** be nested under `replication.connections` — not a top-level `connections` key. Placing it elsewhere (e.g. `connections:` at the root) will cause a "No connection found in config" error.

Only one source database connection is supported per instance. Example:
```yaml
replication:
  connections:
    - type: postgresql
      uri: postgresql://user@host:5432/db
```

#### SSL mode for local databases

Local Postgres instances (including local Supabase via `supabase start`) do not support SSL. The PowerSync service uses pgwire for replication, which defaults to SSL and **does not respect `sslmode=disable` in the URI query string**. You must set `sslmode` as a separate YAML key:

```yaml
replication:
  connections:
    - type: postgresql
      uri: !env PS_DATA_SOURCE_URI
      sslmode: disable   # Required for local Postgres / local Supabase
```

Without this, you will see: `Replication error postgres does not support ssl`.

### Kubernetes / Helm Charts

For Kubernetes deployments (including AWS EKS), use the community-maintained Helm chart. The chart packages the API, replication, compaction, and migration workloads with production defaults.

**Chart repository (source of truth for values, install instructions, and upgrade notes):** https://github.com/powersync-community/powersync-helm-chart

Deploy using standard Helm install/upgrade; configure via `values.yaml` overrides. The PowerSync CLI is not used for Kubernetes deployments.

#### Key Constraints

| Component | Constraint |
|-----------|------------|
| Replication | Default 2 replicas = warm standby. **Only one pod replicates at a time.** Do not add replicas to scale throughput — scale vertically instead. If you drop to `replicas: 1`, set the deployment strategy to `Recreate`. |
| API | Target ~100 connections per pod; hard cap is **200**. Exceeding 200 triggers `PSYNC_S2304` errors. API is stateless — scale out via HPA, not up. |
| `NODE_OPTIONS` | Leave `--max-old-space-size-percentage=80` as-is. V8 tracks the container memory limit automatically; no recalculation is needed when you change `resources.limits.memory`. |

#### Ingress Requirements

- Use a **dedicated subdomain** (e.g. `powersync.example.com`). PowerSync cannot share a host with other services.
- Requires HTTP/2 and WebSocket support. Without HTTP/2, sync stream multiplexing degrades.
- `proxy-buffering: "off"` is **required** for streaming sync — without it responses buffer and stall.
- Set `proxy-read-timeout` and `proxy-send-timeout` to `3600` to keep long-lived sync streams open.
- Terminate TLS at the ingress with a real certificate. The placeholder in `values.yaml` will not work in production.

#### Scaling Beyond a Single Instance

A single replication instance handles roughly 50,000–100,000 concurrent clients depending on row size. Past that, run [multiple instances](https://docs.powersync.com/maintenance-ops/self-hosting/multiple-instances) by installing the chart again under a separate Helm release name with its own bucket storage database. The same source database can be shared across installs.

**Important:** Clients must be **pinned to a specific instance**. Each instance maintains its own copy of bucket data — a client switching instances triggers a full resync. Pin clients via your backend (pass the endpoint explicitly) or compute the endpoint deterministically (e.g. `hash(user_id) % n`). Do not load-balance multiple instances behind one host.

#### Observability

Prometheus metrics are exposed on port `9464`. Enable the chart's `NetworkPolicy` (`networkPolicy.enabled: true`) in production to allow scrapes on that port. Key signals:

| Metric | Note |
|--------|------|
| `powersync_concurrent_connections` | Primary HPA driver. Alert when a pod nears the 200 hard cap. |
| `powersync_replication_lag_seconds` | Alert on sustained spikes. |
| `powersync_replication_storage_size_bytes` | Capacity-plan from the trend. |
| `powersync_operation_storage_size_bytes` | Capacity-plan from the trend. |
| `powersync_data_sent_bytes_total` | Egress cost driver. |

See [Usage Reporting](https://docs.powersync.com/maintenance-ops/self-hosting/usage-reporting#whatiscollected) for the full metric catalog.

### Bucket Storage Database
This is required by PowerSync and can be configured in two different ways. This is separate from the source DB.

| Storage Database | Configuration Reference                                                                                   |
|-----------------|--------------------------------------------------------------------------------------------------------------|
| MongoDB         | [MongoDB Storage](https://docs.powersync.com/configuration/powersync-service/self-hosted-instances#mongodb-storage) |
| Postgres        | [Postgres Storage](https://docs.powersync.com/configuration/powersync-service/self-hosted-instances#postgres-storage) |

### Client Authentication

There are various options when configuring client authentication on a PowerSync Service instance, see [Client Authentication](https://docs.powersync.com/configuration/powersync-service/self-hosted-instances#client_auth) for more information on the options. The options include: JWKS URI, inline JWKs, Supabase Auth, Shared Secrets. Prefer asymmetric keys (RS256, EdDSA, ECDSA) over shared secrets (HS256).

**Important:** There is no `dev: true` auth type in the `client_auth` config schema. It does not exist. For development tokens on self-hosted, configure a real signing key first, then use `powersync generate token`. On PowerSync Cloud, users need to enable development tokens via the dashboard in the Client Auth section of the instance.

### Per-User Sync Limits

By default, each user connection is limited to 1,000 unique buckets and 1,000 parameter query results. Exceeding either limit fails sync with `PSYNC_S2305`. For self-hosted deployments, raise the limits by adding `api.parameters` to `service.yaml`:

```yaml
api:
  parameters:
    max_buckets_per_connection: 5000
    max_parameter_query_results: 5000
```

Set both values. Raising one without the other leaves the connection capped at the limit you did not change. For PowerSync Cloud, request a limit increase (Team and Enterprise plans only). Before raising either limit, review the reduction strategies in [Reducing Bucket Count](https://docs.powersync.com/sync/advanced/reducing-bucket-count).


## PowerSync Cloud Setup

PowerSync Cloud can be set up via the **Dashboard** (UI) or the **CLI**. Both paths require the same four steps. **If any step is missing, the app will be stuck on "Syncing..." with no data.**

| Step | Dashboard | CLI |
|------|-----------|-----|
| 1. Create instance | Dashboard → New Instance | `powersync link cloud --create --project-id=<id>` |
| 2. Connect source DB | Instance Settings → Database | Edit `powersync/service.yaml` → `replication.connections`, then `powersync deploy` |
| 3. Deploy sync config | Instance → Sync Config editor | Edit `powersync/sync-config.yaml`, then `powersync deploy sync-config` |
| 4. Enable client auth | Instance → Client Auth section | Edit `powersync/service.yaml` → `client_auth`, then `powersync deploy service-config` |

**IMPORTANT:** All four steps must be completed. The most common cause of an app stuck on "Syncing..." is a missing or misconfigured step above — typically the database connection or sync config not being deployed.

For full CLI setup workflow, see `references/powersync-cli.md` → Cloud Usage.

See [PowerSync Cloud Instances](https://docs.powersync.com/configuration/powersync-service/cloud-instances.md) for detailed dashboard step-by-step instructions.

## Private Endpoints

> Load this section only when the operator needs to connect PowerSync Cloud to a source database over AWS PrivateLink without public internet exposure.

Private Endpoints use AWS PrivateLink for private networking between your source database and PowerSync Cloud. Available on Team/Enterprise plans. **Dashboard-only — no CLI support yet.** Only AWS is supported; only Postgres (via custom Endpoint Service) and MongoDB Atlas are supported.

**Setup flow:**

1. **Configure an Endpoint Service** in front of your source database and copy its **Service Name** (`com.amazonaws.vpce.<region>.vpce-svc-<id>`):
   - *MongoDB Atlas*: Security → Database & Network Access → Network Access → Private Endpoint → Dedicated Cluster → Create endpoint service. The Atlas cluster does not need to be in the same region as the PowerSync instance; add the PowerSync AWS region under Accepted Endpoint Regions so Atlas accepts connections from it.
   - *Custom Postgres*: Create a Target Group (IP type, TCP, port 5432) → Network Load Balancer → VPC Endpoint Service. Allow principal `arn:aws:iam::131569880293:root` to connect.
2. **Create the Private Endpoint in the Dashboard**: Dashboard → Organization Settings → Private Endpoints → Create. Provide a name, the Service Name from step 1, and the PowerSync region matching your instance. The endpoint starts in `Pending Acceptance` state.
3. **Copy the VPC Endpoint ID** (`vpce-<id>`) from the Dashboard and accept the connection on the Endpoint Service:
   - *Atlas*: Network Access → Private Endpoint → Add Endpoint → Connect Existing Endpoint → enter the VPC Endpoint ID.
   - *Custom Postgres*: AWS Console → VPC → Endpoint Services → accept the connection request matching the VPC Endpoint ID (only needed if you required acceptance when creating the service).
4. **Wait for `Available`** status in the Dashboard:

| Status | Meaning |
|--------|-------|
| `Pending acceptance` | Waiting for you to accept the connection on the Endpoint Service. |
| `Pending` | Being provisioned. |
| `Available` | Ready to use. |
| `Rejected` | Rejected by the Endpoint Service. |
| `Failed` | Creation failed. |

5. **Connect using the Private Endpoint**: Instance → Database Connections → select the endpoint in the Private Endpoint dropdown (only `Available` endpoints in the same region are selectable). For MongoDB Atlas, use the connection string from the Atlas Connect dialog with Private Endpoint selected as the connection type.

**AWS regions supported:** `us-east-1`, `eu-west-1`, `sa-east-1`, `ap-northeast-1`, `ap-southeast-2`. The Private Endpoint must be in the same region as the PowerSync instance; the Endpoint Service itself can be in any AWS region, as long as it accepts connections from the PowerSync instance's region.

## Source Database Setup

Important: For all database user creation below, generate a cryptographically secure password (e.g., `openssl rand -base64 32` or a password manager). Never use placeholder values like `secure_password`, `password`, or `admin123` in production — these are unsafe and must not be suggested to the operator.

See [Source Database Setup](https://docs.powersync.com/configuration/source-db/setup.md) for more information about specific DB host requirements. 

Both PowerSync Cloud and Self-hosted require the same base source database setup.

### Minimum Supported Versions

If the operator's source database version is below the minimum, advise them to upgrade before proceeding.

| Database | Minimum Version |
|----------|----------------|
| PostgreSQL | 11+ |
| MongoDB | 6.0+ |
| MySQL | 5.7+ |
| SQL Server | 2019+ (15.0+), or Azure SQL Database |
| Convex | — (alpha) |

### PostgreSQL Quick Start

```sql
-- 1. Enable logical replication (skip this step for Supabase — it is already enabled)
ALTER SYSTEM SET wal_level = 'logical';
-- Restart PostgreSQL after this

-- 2. Create replication user (replace with a generated secure password—do NOT use "secure_password")
CREATE USER powersync_replication WITH REPLICATION PASSWORD 'YOUR_GENERATED_PASSWORD';

-- 3. Grant read access
GRANT SELECT ON ALL TABLES IN SCHEMA public TO powersync_replication;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT SELECT ON TABLES TO powersync_replication;

-- 4. Create publication (list every table PowerSync should replicate)
CREATE PUBLICATION powersync FOR TABLE users, todos, lists;

-- OR to replicate all current and future tables automatically:
CREATE PUBLICATION powersync FOR ALL TABLES;
```

### MongoDB Quick Start

```javascript
// MongoDB requires a replica set (standalone instances are NOT supported)
// Sharded clusters (including MongoDB Serverless) are NOT supported

// 1. Initialize replica set (if not already)
rs.initiate()

// 2. Create user with required privileges (replace with a generated secure password—do NOT use "secure_password")
// PowerSync needs read access to synced collections AND write access to _powersync_checkpoints
db.createUser({
  user: "powersync",
  pwd: "YOUR_GENERATED_PASSWORD",
  roles: [
    { role: "read", db: "your_database" },
    // Required: find, insert, update, remove, changeStream, createCollection on _powersync_checkpoints
    { role: "readWrite", db: "your_database", collection: "_powersync_checkpoints" },
    // Required: listCollections on the database
    { role: "dbAdmin", db: "your_database" }
  ]
})

// Change streams are used automatically
```

### Azure DocumentDB (Cosmos DB for MongoDB vCore)

> **Experimental.** Azure DocumentDB support is experimental; APIs and behavior may change, and it is not yet covered by SLAs. See [Feature Status](https://docs.powersync.com/resources/feature-status) for production-readiness details.

If the operator is connecting to Azure DocumentDB (formerly Azure Cosmos DB for MongoDB vCore), use `type: mongodb` and point it at the DocumentDB connection string. PowerSync detects DocumentDB automatically. Do not use a separate connector type.

Setup, permissions, and connection steps are the same as MongoDB above. The one difference: `post_images` must be `off` (the default). The `auto_configure` and `read_only` Post Images modes fail on DocumentDB.

#### Supported Variants

Only the vCore engine is supported. If a source does not report as DocumentDB, PowerSync treats it as standard MongoDB.

| Variant | Supported |
| --- | --- |
| Azure DocumentDB / Azure Cosmos DB for MongoDB vCore | Yes |
| Azure Cosmos DB for MongoDB (RU-based) | No |
| Azure Cosmos DB for NoSQL | No |
| Self-hosted open-source DocumentDB engine (`documentdb-local`) | No |

If the operator is on the RU-based model, direct them to the [Microsoft migration guide](https://learn.microsoft.com/en-us/azure/cosmos-db/mongodb/how-to-migrate-documentdb) before connecting.

#### Limitations to Flag Before Connecting

- **Post-images are not supported.** Use `post_images: off` (the default). Updates and deletes still replicate correctly because DocumentDB always includes the full document on change events. Only the `auto_configure` and `read_only` consistency modes are unavailable.
- **Collection drop and rename are not replicated.** If a replicated collection is dropped or renamed, already-synced rows remain under the old name. Recovery requires redeploying Sync Streams to trigger a resync.
- **Documents at or above 15 MiB are dropped** with a logged error. This limit is more reachable on DocumentDB because every change event carries the full document. Large documents also replicate more slowly.
- **Large initial snapshots require storage v3 or later.** On storage v1 or v2, a large or active source can exhaust its change-feed history window before the snapshot completes, causing replication to loop. Storage v3 avoids this by streaming during the snapshot.
- **Do not drop `_powersync_checkpoints`** or delete its documents. Doing so disrupts replication.

### MySQL Quick Start

```sql
-- 1. Enable binary logging and GTID (in my.cnf or my.ini)
-- [mysqld]
-- server-id = 1
-- log_bin = mysql-bin
-- binlog_format = ROW
-- binlog_row_image = FULL
-- gtid_mode = ON
-- enforce-gtid-consistency = ON

-- 2. Create replication user (replace with a generated secure password—do NOT use "secure_password")
CREATE USER 'powersync'@'%' IDENTIFIED BY 'YOUR_GENERATED_PASSWORD';
GRANT REPLICATION SLAVE, REPLICATION CLIENT, RELOAD ON *.* TO 'powersync'@'%';
GRANT SELECT ON your_database.* TO 'powersync'@'%';
FLUSH PRIVILEGES;
```

### SQL Server (MSSQL) Quick Start

```sql
-- 1. Enable CDC at database level
USE [YourDatabase];
EXEC sys.sp_cdc_enable_db;

-- 2. Create PowerSync user (replace with a generated secure password—do NOT use "secure_password")
CREATE LOGIN powersync_user WITH PASSWORD = 'YOUR_GENERATED_PASSWORD', CHECK_POLICY = ON;
CREATE USER powersync_user FOR LOGIN powersync_user;

-- 3. Grant permissions
USE [master];
GRANT VIEW SERVER PERFORMANCE STATE TO powersync_user;

USE [YourDatabase];
GRANT VIEW DATABASE PERFORMANCE STATE TO powersync_user;
ALTER ROLE db_datareader ADD MEMBER powersync_user;
ALTER ROLE cdc_reader ADD MEMBER powersync_user;

-- 4. Create required checkpoints table
CREATE TABLE dbo._powersync_checkpoints (
    id INT IDENTITY PRIMARY KEY,
    last_updated DATETIME NOT NULL DEFAULT (GETDATE())
);
GRANT INSERT, UPDATE ON dbo._powersync_checkpoints TO powersync_user;

-- 5. Enable CDC on checkpoints table
EXEC sys.sp_cdc_enable_table
    @source_schema = N'dbo',
    @source_name   = N'_powersync_checkpoints',
    @role_name     = N'cdc_reader',
    @supports_net_changes = 0;

-- 6. Enable CDC on each synced table
EXEC sys.sp_cdc_enable_table
    @source_schema = N'dbo',
    @source_name   = N'todos',
    @role_name     = N'cdc_reader',
    @supports_net_changes = 0;

-- 7. Optional: Reduce polling interval (default 5s)
-- pollinginterval = 0: fastest, highest CPU
-- pollinginterval = 1: 1 second, good production compromise
EXEC sys.sp_cdc_change_job @job_type = N'capture', @pollinginterval = 1;
```

### Convex Quick Start

> **Experimental.** The Convex replicator is experimental; APIs and behavior may change.

PowerSync replicates from Convex via the Convex Streaming Export API (polling `document_deltas`), not CDC.

**Before connecting PowerSync**, add the `powersync_checkpoints` table and `createCheckpoint` mutation to your Convex deployment. PowerSync calls this mutation to advance the replication cursor:

```typescript
// convex/schema.ts — add to your existing defineSchema
import { defineSchema, defineTable } from 'convex/server';
import { v } from 'convex/values';

export default defineSchema({
  // ... your other tables
  powersync_checkpoints: defineTable({
    last_updated: v.float64()
  })
});
```

```typescript
// convex/powersync_checkpoints.ts
import { mutation } from './_generated/server';

export const createCheckpoint = mutation({
  args: {},
  handler: async (ctx) => {
    const existing = await ctx.db.query('powersync_checkpoints').first();
    if (existing) {
      await ctx.db.patch(existing._id, { last_updated: Date.now() });
    } else {
      await ctx.db.insert('powersync_checkpoints', { last_updated: Date.now() });
    }
  }
});
```

**Deploy key:** In the Convex Dashboard → **Settings** → **General**, generate a deploy key with **Custom permissions** that include `deployment:data:view`. The **Deploy only** option does not provide sufficient access for replication.

**Service YAML (self-hosted):**

```yaml
replication:
  connections:
    - type: convex
      deployment_url: https://<your-deployment>.convex.cloud
      deploy_key: <your-deploy-key>
      # Optional:
      # polling_interval_ms: 1000   # default; lower reduces replication lag
      # request_timeout_ms: 60000   # default
```

**Client ID mapping:** Convex generates `_id` server-side; clients need a stable local ID before a write is uploaded. Use a client-generated UUID column named `id` in your Convex schema, and map relationship foreign keys via `<table>_uuid` columns rather than the Convex `_id`. In Sync Streams, select `uuid AS id`. See [Sync Streams: Convex with ID Mapping](https://docs.powersync.com/sync/streams/examples.md#convex-with-id-mapping) for a complete example.

**Replication latency:** Convex replication is polling-based (default 1000ms interval). Lowering `polling_interval_ms` reduces lag but increases Convex API requests.

**Dropping tables:** Deleting a Convex table in the dashboard does not emit per-document delete rows. If decommissioning a table, use **Clear Table** in the Convex dashboard (or delete documents via mutations) first, then delete the table after those removals have replicated.

## App Backend

PowerSync does not write client-side changes stored in the SQLite database back to the connected source database. Client applications are required to implement the `uploadData` function which should call a backend API to persist the local SQLite changes to the source database. 

| Resource | Description |
|----------|-------------|
| [App Backend Setup](https://docs.powersync.com/configuration/app-backend/setup.md) | Overview of setting up the app backend for PowerSync. |
| [Client-Side Integration with Your Backend](https://docs.powersync.com/configuration/app-backend/client-side-integration.md) | How to implement a "backend connector" and links to example implementations. |

## Authentication

PowerSync Client Applications use JWTs to authenticate agaist the PowerSync Service. 

| Topic                | Resource Link                                                                                          |
|----------------------|------------------------------------------------------------------------------------------------------|
| Authentication Setup | [Authentication Setup](https://docs.powersync.com/configuration/auth/overview.md)                    |
| Development Tokens   | [Development Tokens](https://docs.powersync.com/configuration/auth/development-tokens.md) – Configure tokens for development testing. |
| Custom Auth          | [Custom Auth](https://docs.powersync.com/configuration/auth/custom.md) – Configure custom authentication for PowerSync. |

PowerSync can also integrate with Auth providers, with official guides for the following: 

| Provider   | Resource Link                                                                 |
|------------|-----------------------------------------------------------------------------------|
| Supabase   | [Supabase](https://docs.powersync.com/configuration/auth/supabase-auth.md)            |
| Firebase   | [Firebase](https://docs.powersync.com/configuration/auth/firebase-auth.md)            |
| Auth0      | [Auth0](https://docs.powersync.com/configuration/auth/auth0.md)               |
