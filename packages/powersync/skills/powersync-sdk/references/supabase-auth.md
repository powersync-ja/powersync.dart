---
name: supabase-auth
description: Configuring PowerSync with Supabase — database publication setup, JWT signing keys, Cloud dashboard setup, self-hosted service.yaml config, fetchCredentials() implementation, and error codes
metadata:
  tags: supabase, auth, jwt, jwks, client_auth, fetchCredentials, authentication, hs256, rs256, publication, replica-identity
---

# PowerSync + Supabase Auth

> **Load this when** using Supabase as the backend — covers database publication setup, JWT signing keys, fetchCredentials(), uploadData error handling, and Cloud/self-hosted auth config.

## Table of Contents
- [Supabase Database Setup](#supabase-database-setup)
- [JWT Signing Key Types](#jwt-signing-key-types)
- [PowerSync Cloud Setup](#powersync-cloud-setup)
- [Self-Hosted Config](#self-hosted-serviceyaml-config)
- [fetchCredentials()](#fetchcredentials--client-implementation)
- [Troubleshooting](#troubleshooting)

PowerSync verifies Supabase JWTs directly when connected to a Supabase-hosted Postgres database. This file covers everything needed to configure authentication end-to-end.

## Supabase Database Setup

Supabase already has logical replication enabled at the WAL level. You still need to create a publication so PowerSync knows which tables to replicate, and set `REPLICA IDENTITY FULL` on each table so that DELETE operations include the full row (required for PowerSync to sync deletes to clients).

Run this in the Supabase SQL Editor **after creating your tables**:

```sql
-- Create the PowerSync publication (required)
-- List every table PowerSync should replicate
CREATE PUBLICATION powersync FOR TABLE lists, todos;
```

When you add a new table that PowerSync should replicate, add it to the publication. To replicate all current and future tables automatically (simpler but less precise):

```sql
CREATE PUBLICATION powersync FOR ALL TABLES;
```

### Data API Grants

From May 30, 2026, new Supabase projects no longer auto-expose `public` schema tables to the Data API. Without explicit grants, `supabase-js` returns `42501: permission denied for table <name>` before RLS is evaluated. Grant each table the client writes to:

```sql
-- Required for supabase-js write operations on new Supabase projects (May 2026+)
-- Omitting this causes: 42501: permission denied for table <name>
grant select, insert, update, delete on public.lists to authenticated;
grant select, insert, update, delete on public.todos to authenticated;
```

Grants control which Postgres roles can reach a table through the Data API. RLS then filters which rows that role can read or modify. Both are required — a grant without RLS exposes all rows; RLS without a grant blocks all access.

## JWT Signing Key Types

Supabase projects use one of two signing key types. **Check which your project uses** at [Project Settings → JWT](https://supabase.com/dashboard/project/_/settings/jwt) in the Supabase Dashboard before configuring PowerSync.

| Type | Algorithm | Notes |
|------|-----------|-------|
| **New JWT signing keys** | RS256 (asymmetric) | Recommended. PowerSync auto-detects from the connection string. |
| **Legacy JWT signing keys** | HS256 (symmetric) | Requires supplying the JWT secret to PowerSync. Consider migrating. |

---

## PowerSync Cloud Setup

Configure via the **Client Auth** section of your instance in the [PowerSync Dashboard](https://dashboard.powersync.com/).

### New JWT signing keys (recommended)

1. Enable the **Use Supabase Auth** checkbox.
2. Leave the **Supabase JWT Secret** field empty.
3. Click **Save and Deploy**.

PowerSync auto-detects your Supabase project from the database connection string and configures the JWKS URI (`https://<project-ref>.supabase.co/auth/v1/.well-known/jwks.json`) and JWT audience (`authenticated`) automatically.

### Legacy JWT signing keys (HS256)

1. Enable the **Use Supabase Auth** checkbox.
2. Copy your **JWT Secret** from Supabase → [Project Settings → JWT](https://supabase.com/dashboard/project/_/settings/jwt).
3. Paste it into the **Supabase JWT Secret (Legacy)** field.
4. Click **Save and Deploy**.

### Manual JWKS (non-standard connections)

Use this when PowerSync cannot auto-detect your Supabase project (self-hosted Supabase, local Docker, non-standard connection string):

1. Leave **Use Supabase Auth** unchecked.
2. Add a **JWKS URI**, e.g. `http://localhost:54321/auth/v1/.well-known/jwks.json`.
3. Add `authenticated` as an accepted **JWT Audience**.
4. Click **Save and Deploy**.

> Skipping the `authenticated` audience causes `PSYNC_S2105` errors — see Troubleshooting below.

---

## Self-Hosted `service.yaml` Config

### New JWT signing keys (recommended)

PowerSync auto-detects the Supabase project from the connection string:

```yaml
client_auth:
  supabase: true
```

PowerSync automatically sets:
- JWKS URI: `https://<project-ref>.supabase.co/auth/v1/.well-known/jwks.json`
- Audience: `authenticated`

### Legacy JWT signing keys (HS256)

```yaml
client_auth:
  supabase: true
  supabase_jwt_secret: !env PS_SUPABASE_JWT_SECRET
```

Get the secret from Supabase → Project Settings → JWT. Use `!env` to avoid hardcoding secrets.

### Local Supabase (`supabase start`)

**IMPORTANT:** Local Supabase (via `supabase start`) uses **ES256 asymmetric JWT signing keys**, not the legacy HS256 shared secret. This means:

- `supabase: true` alone **will not work** — it cannot auto-detect a local project from the connection string.
- `supabase: true` + `supabase_jwt_secret` **will not work** — it registers an HS256 key, but local Supabase issues ES256 tokens with a `kid` that doesn't match.
- You **must** use manual JWKS pointing to the local Supabase JWKS endpoint.

The error you'll see if misconfigured:
```
PSYNC_S2101: Could not find an appropriate key in the keystore. The key is missing or no key matched the token KID
```
With details showing: `Known keys: <kid: *, kty: oct, alg: HS256>` but the token has `alg: ES256` with a specific `kid`.

**Correct config for local Supabase:**

```yaml
client_auth:
  # Use host.docker.internal to reach the host machine from inside the PowerSync Docker container.
  # Alternatively, use the Supabase Kong container name (e.g. supabase_kong_<project-id>)
  # if both are on the same Docker network.
  jwks_uri: http://host.docker.internal:54321/auth/v1/.well-known/jwks.json
  audience:
    - authenticated
  block_local_jwks: false
```

Key details:
- Use `host.docker.internal` or the Supabase container name (not `localhost`) because this URI is resolved **from inside the PowerSync Docker container**.
- `block_local_jwks: false` is required because `host.docker.internal` resolves to a local/private IP, which PowerSync blocks by default.
- The well-known local Supabase JWT secret (`super-secret-jwt-token-with-at-least-32-characters-long`) is **not used** for token signing in newer Supabase versions — it's only used for the service role key and anon key.

**SSL for local Supabase Postgres:** Local Supabase does not support SSL. You **must** set `sslmode: disable` on the replication connection in `service.yaml`. The `sslmode=disable` query string in the URI alone does not work — pgwire ignores it. Use the YAML key instead:

```yaml
replication:
  connections:
    - type: postgresql
      uri: postgresql://postgres@host.docker.internal:54322/postgres
      password: !env PS_SUPABASE_DB_PASSWORD
      sslmode: disable
```

Without this you will see: `Replication error postgres does not support ssl`.

Local Supabase database credentials are printed by `supabase status`. Supply the password to the PowerSync service container via the `PS_SUPABASE_DB_PASSWORD` environment variable. The service only substitutes `!env` variables whose names start with `PS_`.

You can verify your local Supabase is using ES256 by checking:
```bash
curl -s http://127.0.0.1:54321/auth/v1/.well-known/jwks.json
# Returns: {"keys":[{"alg":"ES256","crv":"P-256","kty":"EC",...}]}
```

### Manual JWKS (other non-standard connections)

Use when `supabase: true` cannot auto-detect the project (e.g. self-hosted Supabase, custom auth proxy):

```yaml
client_auth:
  jwks_uri: http://localhost:54321/auth/v1/.well-known/jwks.json
  audience:
    - authenticated
```

> Do **not** combine `supabase: true` with `jwks_uri`. Use one or the other.

---

## `fetchCredentials()` — Client Implementation

**Prerequisite:** `fetchCredentials()` requires an active Supabase auth session. PowerSync calls it automatically whenever a token is needed, but if no session exists (user not signed in), it will throw and sync will not start. **You must sign the user in before calling `db.connect()`.**

- If your app requires explicit sign-in (email/password, OAuth, magic link), connect PowerSync only after the sign-in completes.
- If anonymous access is acceptable, use the anonymous sign-in pattern below.
- If anonymous auth is disabled on your Supabase project, there is no silent fallback — the agent must gate `db.connect()` behind an explicit auth flow.

`fetchCredentials()` in your backend connector should return the Supabase session JWT. The examples below use the JS Supabase client; equivalent patterns exist for [Dart](https://github.com/powersync-ja/powersync.dart/blob/main/demos/supabase-todolist/lib/powersync.dart) and [Kotlin](https://github.com/powersync-ja/powersync-kotlin/blob/main/connectors/supabase/src/commonMain/kotlin/com/powersync/connector/supabase/SupabaseConnector.kt).

### Standard Supabase Auth (JS/TS)

Use this when users sign in explicitly (email, OAuth, magic link). Call `db.connect(connector)` only after `supabase.auth.signIn*` succeeds.

```ts
import { createClient } from '@supabase/supabase-js';
import type { PowerSyncBackendConnector, PowerSyncCredentials } from '@powersync/web'; // or @powersync/react-native

const supabase = createClient(SUPABASE_URL, SUPABASE_ANON_KEY);

export const connector: PowerSyncBackendConnector = {
  async fetchCredentials(): Promise<PowerSyncCredentials> {
    const { data: { session }, error } = await supabase.auth.getSession();
    if (error || !session) throw error ?? new Error('No session');
    return {
      endpoint: POWERSYNC_URL,
      token: session.access_token,
      expiresAt: new Date(session.expires_at! * 1000),
    };
  },
  // ...uploadData
};
```

> **Publishable keys:** New Supabase projects use publishable keys (prefixed `sb_publishable_…`) in place of the legacy anon key. Use it as the value for `SUPABASE_ANON_KEY` — the `createClient()` call is unchanged.

### Anonymous Sign-In (JS/TS)

Use this when you want sync to work without an explicit sign-in step. Requires **anonymous sign-ins to be enabled** in Supabase (Dashboard → Authentication → Providers → Anonymous). If disabled, `signInAnonymously()` returns an error and sync fails silently.

```ts
async fetchCredentials(): Promise<PowerSyncCredentials> {
  let { data: { session } } = await supabase.auth.getSession();
  if (!session) {
    const { data, error } = await supabase.auth.signInAnonymously();
    if (error) throw error; // Will throw if anonymous auth is disabled
    session = data.session!;
  }
  return {
    endpoint: POWERSYNC_URL,
    token: session.access_token,
    expiresAt: new Date(session.expires_at! * 1000),
  };
},
```

`fetchCredentials` is called automatically on reconnect — always return a fresh token, never a cached one.

### `uploadData()` — Writing Changes Back to Supabase

For Supabase backends, `uploadData` writes client-side changes directly to Supabase. **`transaction.complete()` is mandatory** — without it the upload queue stalls permanently.

#### Error handling strategy

| Error type | What to do | Why |
|-----------|-----------|-----|
| Network / 5xx (transient) | `throw error` — do not call `transaction.complete()` | PowerSync retries with backoff |
| 4xx / RLS violation (permanent) | Call `transaction.complete()`, log the error | 4xx blocks the queue forever; better to skip and log than halt all future writes |
| Validation error | Call `transaction.complete()`, surface via a synced error table | Data errors are permanent; retrying won't fix them |

The Supabase JS client returns errors as `{ error: PostgrestError }` rather than throwing HTTP status codes — check `error.code` or `error.message` to distinguish permanent failures (constraint violations, RLS denials) from transient ones. Supabase RLS errors return `{ code: '42501' }` (PostgreSQL insufficient_privilege).

```ts
import type { AbstractPowerSyncDatabase, PowerSyncBackendConnector, UpdateType } from '@powersync/web';

export const connector: PowerSyncBackendConnector = {
  async fetchCredentials() { /* ... see above ... */ },

  async uploadData(database: AbstractPowerSyncDatabase): Promise<void> {
    const transaction = await database.getNextCrudTransaction();
    if (!transaction) return;

    try {
      for (const op of transaction.crud) {
        const { op: opType, table, opData, id } = op;
        let result: { error: any };
        if (opType === UpdateType.PUT) {
          result = await supabase.from(table).upsert({ ...opData, id });
        } else if (opType === UpdateType.PATCH) {
          result = await supabase.from(table).update(opData).eq('id', id);
        } else {
          result = await supabase.from(table).delete().eq('id', id);
        }
        if (result.error) throw result.error;
      }
      await transaction.complete(); // REQUIRED — advances the queue
    } catch (error: any) {
      // Permanent failures (RLS violation, constraint error, 4xx-equivalent):
      // complete the transaction so the queue can advance. Log for debugging.
      const isPermanent = error?.code === '42501' || error?.status === 400;
      if (isPermanent) {
        console.error('Permanent upload error, skipping:', error);
        await transaction.complete();
        return;
      }
      // Transient failures: throw so PowerSync retries with backoff.
      throw error;
    }
  }
};
```

**Important:** Your tables need both Data API grants and RLS policies. Without `grant … on public.<table> to authenticated`, `supabase-js` returns `42501: permission denied for table` before RLS is evaluated — see [Data API Grants](#data-api-grants). Without RLS policies, any authenticated user can read and write all rows.

### Getting the PowerSync Instance URL

See `references/powersync-cli.md` § "Getting POWERSYNC_URL" — the instance ID is printed by `powersync link cloud --create` and the URL pattern is `https://<instance-id>.powersync.journeyapps.com`. Write it to `.env` before writing app code.

For self-hosted, the URL is whatever hostname your PowerSync Docker service is exposed on (e.g. `http://localhost:8080`).

---

## `auth.user_id()` in Sync Streams

`auth.user_id()` returns the Supabase user's UUID (the `sub` claim from the JWT). Use it to scope sync queries per user:

```yaml
streams:
  my_todos:
    auto_subscribe: true
    query: SELECT * FROM todos WHERE user_id = auth.user_id()
```

For Sync Rules (legacy), use `request.user_id()` instead.

---

## Kotlin: Built-in Supabase Connector

The Kotlin SDK includes a first-party Supabase connector that handles `fetchCredentials` and session management automatically:

```kotlin
// build.gradle.kts
implementation("com.powersync:connector-supabase:$powersyncVersion")
```

```kotlin
val connector = SupabaseConnector(
    supabaseUrl = "https://your-project.supabase.co",
    supabaseKey = "your-anon-key",
    powerSyncEndpoint = "https://your-instance.powersync.journeyapps.com",
)
```

---

## Troubleshooting

### `PSYNC_S2101` — Could not find an appropriate key in the keystore

PowerSync cannot verify the JWT signature. Check the error logs for `Known keys` and `tokenDetails` to diagnose the mismatch.

| Cause | Symptom | Solution |
|-------|---------|----------|
| **Local Supabase with `supabase_jwt_secret`** | Known keys show `HS256` but token uses `ES256` with a specific `kid` | Local Supabase uses ES256 asymmetric keys. Switch to manual JWKS config — see "Local Supabase" section above. |
| Incomplete Supabase key migration | Token `alg` doesn't match keystore | Complete the "Rotate to asymmetric JWTs" step in the [Supabase migration guide](https://supabase.com/blog/jwt-signing-keys#start-using-asymmetric-jwts-today). |
| Stale tokens after migration | Old tokens fail, new logins work | Have users sign out and back in to receive new tokens. |
| Auto-detection failed | `supabase: true` but no keys registered | PowerSync couldn't detect your Supabase project from the connection string. Use manual JWKS config. |
| Wrong JWT secret | HS256 verification fails | For legacy HS256 keys, verify the secret matches Supabase → Project Settings → JWT. |
| `block_local_jwks` blocking JWKS fetch | JWKS URI resolves to private IP, keys never fetched | Set `block_local_jwks: false` for local development. |

After any `service.yaml` auth change, restart the service to pick it up: `powersync docker reset` (self-hosted) or `powersync deploy service-config` (Cloud).

### `PSYNC_S2105` — JWT payload is missing a required claim "aud"

Using manual JWKS config without specifying an audience. Add `authenticated` to the audience list (Cloud dashboard or `audience: [authenticated]` in `service.yaml`).

### Auto-detection warning

If you see:
```
Supabase Auth is enabled, but no Supabase connection string found. Skipping Supabase JWKS URL configuration.
```

PowerSync couldn't detect your project from the connection string. Switch to manual JWKS configuration.

---

## Migrating from Legacy to New JWT Signing Keys

1. Follow **all steps** in the [Supabase JWT migration guide](https://supabase.com/blog/jwt-signing-keys#start-using-asymmetric-jwts-today), including the **"Rotate to asymmetric JWTs"** step. The migration is not complete without this step.
2. Update PowerSync config:
   - **Cloud / self-hosted with standard connection**: No change needed — PowerSync auto-detects the new JWKS. Remove any previously set legacy JWT secret.
   - **Manual JWKS**: Ensure `jwks_uri` points to the Supabase JWKS endpoint and `authenticated` is in the audience list.
3. Have all users sign out and sign back in to receive tokens signed with the new keys.
