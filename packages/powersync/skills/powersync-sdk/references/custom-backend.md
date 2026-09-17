---
name: custom-backend
description: Building a custom backend for PowerSync — server-side API for uploadData, custom JWT auth, JWKS endpoints, and client-side connector implementation
metadata:
  tags: backend, custom, jwt, auth, express, fastify, uploadData, api, non-supabase
---

# Custom Backend for PowerSync

> **Load this when** building a PowerSync integration without Supabase — custom auth, custom backend API, or any non-Supabase database.

## Table of Contents
- [Architecture Recap](#architecture-recap)
- [1. Custom JWT Auth](#1-custom-jwt-auth)
- [2. Backend API for uploadData](#2-backend-api-for-uploaddata)
- [3. Client-Side Connector](#3-client-side-connector-custom-backend)
- [Common Pitfalls](#common-pitfalls)

Use this file when building a PowerSync integration **without Supabase** — your own auth and a backend API that receives writes from the client's upload queue.

For **source database setup** (Postgres replication, MongoDB replica set, MySQL binlog, MSSQL CDC), see `references/powersync-service.md` § "Source Database Setup".

For **service.yaml configuration** (Cloud or self-hosted templates), see `references/powersync-service.md`.

| Resource | Description |
|----------|-------------|
| [App Backend Setup](https://docs.powersync.com/configuration/app-backend/setup.md) | Overview of setting up the app backend for PowerSync. |
| [Client-Side Integration](https://docs.powersync.com/configuration/app-backend/client-side-integration.md) | How to implement a backend connector. |
| [Writing Client-Side Changes](https://docs.powersync.com/usage/writing-client-side-changes-to-your-backend.md) | Detailed guide on the upload queue and backend write flow. |
| [Custom Auth](https://docs.powersync.com/configuration/auth/custom.md) | JWT auth setup for non-Supabase backends. |
| [Development Tokens](https://docs.powersync.com/configuration/auth/development-tokens.md) | Generate tokens for local development and testing. |

## Architecture Recap

```
Client App                    Your Backend API              Source Database
  |                                |                           |
  |-- uploadData() POST ---------->|--- INSERT/UPDATE/DELETE -->|
  |                                |<-- 2xx response -----------|
  |                                                            |
PowerSync Service <-------------- CDC / logical replication ---|
  |
  |-- streams synced data -------> Client App (local SQLite)
```

Key rule: **client writes never go through PowerSync**. The upload queue sends writes to YOUR backend API. PowerSync only handles the read/sync path.

> **Convex exception:** If the source database is Convex, `uploadData()` calls Convex mutations directly — no intermediate REST API is required for the write path. If using Convex Auth tokens for PowerSync client authentication, configure `client_auth.audience: [convex]` in `service.yaml`. See `references/powersync-service.md` § "Convex Quick Start".

## 1. Custom JWT Auth

PowerSync verifies JWTs from client apps. Without Supabase, you must generate and serve your own JWTs and JWKS.

### Supported Algorithms

| Algorithm | Type | Recommendation |
|-----------|------|----------------|
| RS256, RS384, RS512 | Asymmetric (RSA) | Recommended for production |
| ES256, ES384, ES512 | Asymmetric (ECDSA) | Recommended for production |
| EdDSA (Ed25519, Ed448) | Asymmetric | Recommended for production |
| HS256 | Symmetric | Development only |

### Required JWT Claims

| Claim | Required | Description |
|-------|----------|-------------|
| `sub` | Yes | User ID — returned by `auth.user_id()` in sync config queries |
| `aud` | Yes | Must match the `audience` configured in PowerSync service config |
| `iat` | Yes | Issued-at timestamp (seconds since epoch) |
| `exp` | Yes | Expiry timestamp — must be at most 86400 seconds (24h) after `iat` |
| `kid` | Yes (for JWKS) | Key ID — must match a key in the JWKS |

### Generate RSA Key Pair

```bash
# Generate a 2048-bit RSA private key
openssl genpkey -algorithm RSA -out private.pem -pkeyopt rsa_keygen_bits:2048

# Extract the public key
openssl rsa -in private.pem -pubout -out public.pem
```

### Implement a JWKS Endpoint

Your backend must serve a `/.well-known/jwks.json` endpoint. PowerSync fetches this every few minutes to get the public keys for token verification.

```ts
// Using jose library: npm install jose
import { exportJWK, importPKCS8 } from 'jose';
import { readFileSync } from 'fs';

const privateKeyPem = readFileSync('./private.pem', 'utf-8');
const KID = 'powersync-key-1'; // Stable key identifier

let cachedJwk: any = null;

export async function getJWKS() {
  if (!cachedJwk) {
    const privateKey = await importPKCS8(privateKeyPem, 'RS256');
    const jwk = await exportJWK(privateKey);
    // Only include the public key components
    cachedJwk = {
      kty: jwk.kty,
      n: jwk.n,
      e: jwk.e,
      alg: 'RS256',
      kid: KID,
      use: 'sig',
    };
  }
  return { keys: [cachedJwk] };
}
```

### Generate JWTs (Token Endpoint)

The token endpoint generates a PowerSync JWT for an already-authenticated user. It does **not** handle user login — your app authenticates users separately via sessions, OAuth, or whatever mechanism you use.

```ts
import { SignJWT, importPKCS8 } from 'jose';
import { readFileSync } from 'fs';

const privateKeyPem = readFileSync('./private.pem', 'utf-8');
const KID = 'powersync-key-1';
const POWERSYNC_URL = process.env.POWERSYNC_URL || 'http://localhost:8080';

export async function generateToken(userId: string): Promise<string> {
  const privateKey = await importPKCS8(privateKeyPem, 'RS256');

  return new SignJWT({})
    .setProtectedHeader({ alg: 'RS256', kid: KID })
    .setSubject(userId)
    .setIssuedAt()
    .setIssuer('your-app')        // Must match issuer config if set
    .setAudience(POWERSYNC_URL)   // Must match audience config
    .setExpirationTime('5m')      // Short-lived; max 24h, PowerSync refreshes automatically
    .sign(privateKey);
}
```

### Service Config for Custom Auth

See `references/powersync-service.md` § "Minimal Cloud service.yaml Examples" for the Cloud + Custom Auth template, or § "Complete service.yaml Example" for self-hosted.

For local development with `host.docker.internal`, set `block_local_jwks: false` in service config when the JWKS URI resolves to a private IP.

### Development Tokens

For quick development without full auth, configure a signing key in `service.yaml` and use the CLI:

```bash
powersync generate token --user-id "test-user-123"
```

This requires `client_auth` to be configured with at least one key. See [Development Tokens](https://docs.powersync.com/configuration/auth/development-tokens.md).

### Key Rotation

When using a JWKS URI:

1. Add the new key to the JWKS endpoint (keep the old key).
2. Wait 5 minutes for PowerSync to refresh its key cache.
3. Start signing tokens with the new key.
4. Wait for all old tokens to expire (up to their `exp`).
5. Remove the old key from the JWKS endpoint.

## 2. Backend API for uploadData

The client's `uploadData()` sends pending writes to your backend API. Your backend must:

1. Accept the write operations.
2. Apply them to the database **synchronously** (do not queue for later processing).
3. Return 2xx — even for validation errors.

### Request/Response Contract

| Scenario | HTTP Status | Effect on Upload Queue |
|----------|-------------|----------------------|
| Success | 2xx | `transaction.complete()` advances the queue |
| Validation error | 2xx (with error details in body) | Queue advances — surface errors via a synced table |
| Transient error (DB down) | 5xx | PowerSync retries with backoff |
| Auth error / permanent failure | 4xx | **Blocks the queue permanently** — never return 4xx for data errors |

### CrudEntry Format (What the Client Sends)

Each operation in the upload queue has this shape:

```ts
interface CrudEntry {
  id: string;              // Row ID (UUID)
  op: 'PUT' | 'PATCH' | 'DELETE';
  table: string;           // Table name
  opData?: Record<string, any>;  // Column values (undefined for DELETE)
  transactionId?: number;  // Groups ops from the same writeTransaction()
}
```

- `PUT` = full insert or replace (new row or complete overwrite)
- `PATCH` = partial update (opData contains only changed columns)
- `DELETE` = deletion (opData is undefined)

### Example: Express Backend

```ts
import express from 'express';
import pg from 'pg';

const app = express();
app.use(express.json());

const pool = new pg.Pool({ connectionString: process.env.DATABASE_URL });

// Token endpoint — client calls this in fetchCredentials()
app.get('/api/auth/token', async (req, res) => {
  const userId = req.query.user_id as string;
  if (!userId) return res.status(400).json({ error: 'user_id is required' });

  const token = await generateToken(userId);
  res.json({
    token,
    powersync_url: process.env.POWERSYNC_URL,
  });
});

// JWKS endpoint — PowerSync fetches this to verify tokens
app.get('/.well-known/jwks.json', async (_req, res) => {
  const jwks = await getJWKS();
  res.json(jwks);
});

// Upload endpoint — client's uploadData() calls this
app.post('/api/powersync/upload', async (req, res) => {
  const { operations } = req.body;

  const client = await pool.connect();
  try {
    await client.query('BEGIN');

    for (const op of operations) {
      switch (op.op) {
        case 'PUT': {
          const columns = Object.keys(op.opData);
          const values = Object.values(op.opData);
          const placeholders = columns.map((_, i) => `$${i + 2}`).join(', ');
          const updateSet = columns.map((col, i) => `${col} = $${i + 2}`).join(', ');
          await client.query(
            `INSERT INTO ${op.table} (id, ${columns.join(', ')})
             VALUES ($1, ${placeholders})
             ON CONFLICT (id) DO UPDATE SET ${updateSet}`,
            [op.id, ...values]
          );
          break;
        }
        case 'PATCH': {
          const columns = Object.keys(op.opData!);
          const values = Object.values(op.opData!);
          const setClause = columns.map((col, i) => `${col} = $${i + 2}`).join(', ');
          await client.query(
            `UPDATE ${op.table} SET ${setClause} WHERE id = $1`,
            [op.id, ...values]
          );
          break;
        }
        case 'DELETE': {
          await client.query(
            `DELETE FROM ${op.table} WHERE id = $1`,
            [op.id]
          );
          break;
        }
      }
    }

    await client.query('COMMIT');
    res.json({ success: true });
  } catch (err) {
    await client.query('ROLLBACK');
    console.error('Upload error:', err);
    // Return 2xx with error details — do NOT return 4xx
    res.json({ success: false, error: (err as Error).message });
  } finally {
    client.release();
  }
});

app.listen(3001, () => console.log('Backend running on :3001'));
```

**IMPORTANT:** The upload endpoint example above uses string interpolation for table names. In production, validate `op.table` against an allowlist:

```ts
const ALLOWED_TABLES = new Set(['posts', 'comments', 'users']);
if (!ALLOWED_TABLES.has(op.table)) {
  return res.json({ success: false, error: `Unknown table: ${op.table}` });
}
```

### Boolean Conversion

PowerSync stores booleans as integers (0/1) in SQLite. If your database uses native `boolean` columns, convert before writing:

```ts
if (op.table === 'posts' && op.opData?.is_published !== undefined) {
  op.opData.is_published = Boolean(op.opData.is_published);
}
```

## 3. Client-Side Connector (Custom Backend)

### fetchCredentials

```ts
import type { PowerSyncBackendConnector, PowerSyncCredentials } from '@powersync/web';

const BACKEND_URL = import.meta.env.VITE_BACKEND_URL;     // e.g. http://localhost:3001
const POWERSYNC_URL = import.meta.env.VITE_POWERSYNC_URL;  // e.g. http://localhost:8080

export class CustomConnector implements PowerSyncBackendConnector {
  private userId: string;
  private token: string | null = null;

  constructor(userId: string) {
    this.userId = userId;
  }

  async fetchCredentials(): Promise<PowerSyncCredentials> {
    const res = await fetch(
      `${BACKEND_URL}/api/auth/token?user_id=${encodeURIComponent(this.userId)}`
    );
    if (!res.ok) throw new Error('Failed to get PowerSync token');

    const { token, powersync_url } = await res.json();
    this.token = token;

    return {
      endpoint: powersync_url || POWERSYNC_URL,
      token,
    };
  }
```

### uploadData

```ts
  async uploadData(database: AbstractPowerSyncDatabase): Promise<void> {
    const transaction = await database.getNextCrudTransaction();
    if (!transaction) return;

    try {
      const operations = transaction.crud.map((op) => ({
        id: op.id,
        op: op.op,
        table: op.table,
        opData: op.opData,
      }));

      const res = await fetch(`${BACKEND_URL}/api/powersync/upload`, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'Authorization': `Bearer ${this.token}`,
        },
        body: JSON.stringify({ operations }),
      });

      if (!res.ok) throw new Error(`Upload failed: ${res.status}`);

      const result = await res.json();
      if (!result.success) {
        console.warn('Upload had errors:', result.error);
      }

      // MUST call complete() — without this the queue stalls permanently
      await transaction.complete();
    } catch (ex) {
      throw ex;
    }
  }
}
```

## Common Pitfalls

1. **4xx from upload endpoint** — Blocks the upload queue **permanently**. Always return 2xx, even for validation errors.
2. **Async processing of writes** — PowerSync expects writes reflected in the database immediately. Do not queue writes.
3. **Token expiry > 24h** — PowerSync rejects tokens with `exp - iat > 86400`. Use short-lived tokens (1h production, max 24h dev).
4. **`kid` mismatch** — JWT header `kid` must match a key in your JWKS. Causes `PSYNC_S2101`.
5. **`block_local_jwks` not set** — JWKS URIs resolving to private IPs are blocked by default. Set `block_local_jwks: false` for local dev.
6. **Wrong `endpoint` in `fetchCredentials()`** — Must be the PowerSync URL, not your backend URL. Causes 404 on `/sync/stream`.
