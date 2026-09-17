---
name: onboarding-custom
description: Step-by-step onboarding recipe for any app using a custom backend (non-Supabase) with PowerSync — orchestrates the correct sequence and points to canonical references for each step
metadata:
  tags: onboarding, custom, backend, recipe, cloud, self-hosted
---

# Custom Backend + PowerSync Onboarding

> **Load this when** onboarding an app onto PowerSync with a non-Supabase backend (custom Postgres, MongoDB, MySQL, MSSQL).

Use this recipe when onboarding any app onto PowerSync with a **non-Supabase backend** — your own database, your own auth, and your own backend API. Works for all platforms (web, React Native, Flutter, Kotlin, Swift, .NET, etc.) and both Cloud and self-hosted.

**CLI-first.** See `references/powersync-cli.md`. Fall back to the dashboard (Cloud) or manual Docker config (self-hosted) only if the CLI is unavailable or the operator explicitly prefers it.

## Required Inputs

Collect before writing any code:

- **Cloud or self-hosted** — which PowerSync hosting model
- **Database type** — Postgres, MongoDB, MySQL, or MSSQL
- Database connection details (host, port, database, username, password or connection URI)
- Whether a PowerSync instance already exists
- PowerSync instance URL (if instance exists)
- Instance ID (if using CLI with an existing Cloud instance)
- Project ID (if using CLI to create a new Cloud instance via `powersync link cloud --create`); also Org ID if the PAT covers multiple organizations
- How the operator wants to handle auth (custom JWT, third-party provider like Auth0/Firebase, or dev tokens)
- Whether they have an existing backend API or need to create one

Only ask for secrets (database password, private keys) when you are at the step that actually needs them.

## Workflow

Follow this sequence exactly. **Do not skip ahead to app code.**

### Phase 1: Service Setup

1. **Confirm the path.** Verify: PowerSync (Cloud or self-hosted) + custom backend + your platform.

2. **Set up the source database.** Load `references/powersync-service.md` § "Source Database Setup" for the relevant quick start (Postgres, MongoDB, MySQL, or MSSQL). Present the exact SQL to the operator and ask them to confirm it is done.

3. **Keep credentials in `.env`, never hardcoded.** As soon as database details are available, record them there:
   ```
   POWERSYNC_URL=https://your-instance.powersync.journeyapps.com  # or http://localhost:8080 for self-hosted
   # Cloud service.yaml uses PS_DATABASE_URI; self-hosted Docker uses PS_DATA_SOURCE_URI
   PS_DATABASE_URI=postgresql://user@host:5432/db      # Cloud
   # PS_DATA_SOURCE_URI=postgresql://user@host:5432/db # Self-hosted (set in powersync/docker/.env)
   BACKEND_URL=http://localhost:3001
   ```
   Both `service.yaml` (via `!env` tags) and app code depend on these values.

4. **Scaffold and configure PowerSync.**
   - **Cloud:** `powersync init cloud` → edit config → `powersync link cloud --create --project-id=<id>` → deploy
   - **Self-hosted:** `powersync init self-hosted` → `powersync docker configure` → edit config → `powersync docker start`

   See `references/powersync-cli.md` for the full CLI reference.

5. **Configure service.yaml.** See `references/powersync-service.md` for service.yaml templates:
   - Cloud + Custom Auth: § "Minimal Cloud service.yaml Examples"
   - Self-hosted: § "Complete service.yaml Example"

6. **Configure client auth.** See `references/custom-backend.md` § "Custom JWT Auth" for JWKS setup, or use `powersync generate token --subject=user-1` for dev tokens after configuring at least one signing key.

7. **Generate sync config.** Load `references/sync-config.md`. Use Sync Streams with `config: edition: 3`.

8. **Deploy config.**
   - **Cloud:** `powersync deploy service-config` then `powersync deploy sync-config`
   - **Self-hosted:** `powersync docker reset` (picks up config changes)

### Phase 2: Backend API

Only start this after the PowerSync service is configured and running.

9. **Create the backend API.** Load `references/custom-backend.md` for full details. Your backend needs three endpoints: JWKS (`/.well-known/jwks.json`), token (`/api/auth/token`), and upload (`/api/powersync/upload`).

10. **Set up JWT signing.** See `references/custom-backend.md` § "Custom JWT Auth" for key generation, JWKS endpoint, and token endpoint code.

11. **Verify the auth chain.** Confirm JWKS endpoint returns valid keys, token endpoint returns a signed JWT, and PowerSync can reach the JWKS URI (use `host.docker.internal` from Docker, not `localhost`).

### Phase 3: Backend Readiness Gate

Do not proceed to app code until all items are verified:

- [ ] PowerSync instance exists and is running
- [ ] Source database connection is configured
- [ ] Source database replication/publication/CDC is set up
- [ ] Sync config is deployed with `config: edition: 3`
- [ ] Client auth is configured (JWKS URI or inline keys)
- [ ] Backend API is running (JWKS + token + upload endpoints)
- [ ] All credentials and URLs are in `.env`

If any item is missing, finish it before writing app code.

### Phase 4: App Integration

Only after Phase 3 is complete.

12. **Install SDK packages.** Load the SDK reference file for your platform — see the SDK table in `SKILL.md`.

13. **Define the client schema.** Generate from deployed sync config:
    ```bash
    powersync generate schema --output=ts --output-path=./src/schema.ts
    ```
    Or write manually — but never define the `id` column (it is automatic).

14. **Implement the backend connector.** See `references/custom-backend.md` § "Client-Side Connector" for `fetchCredentials()` and `uploadData()` code. Critical: `transaction.complete()` is mandatory — without it the queue stalls permanently.

15. **Initialize PowerSync and connect.**
    - `connect()` is fire-and-forget — use `waitForFirstSync()` if you need readiness.
    - Use `disconnectAndClear()` on logout or user switch.

16. **Switch reads to local SQLite** and test offline behavior.

## If the App Is Stuck on `Syncing...`

See `references/powersync-debug.md` § "First Response When the UI Is Stuck on `Syncing...`" — check backend readiness before inspecting frontend code.
