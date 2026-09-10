---
name: powersync-sdk
description: "Best practices for building and maintaining applications with PowerSync: Cloud and self-hosted setup, sync configuration, client SDK usage, backend integration (Supabase, custom Postgres, MongoDB, MySQL, MSSQL), schema changes, watch and reactive queries (useQuery), attachments, the upload queue, and debugging. Use this skill whenever the user mentions PowerSync, a @powersync/* package (@powersync/web, @powersync/react-native, @powersync/node), the powersync Flutter/Dart package, wa-sqlite, offline-first sync, local-first architecture, sync rules, sync streams, uploadData, fetchCredentials, disconnectAndClear, logout or user switching in a synced app, real-time data replication, Electric Cloud migration, Electric Shapes, an app stuck on Syncing, data not syncing, or wants to add offline-capable sync to a mobile or web app, even if they do not explicitly name PowerSync."
when_to_use: "Load before any data, schema, sync, or auth change in a project that already uses PowerSync, even if the request never mentions sync. Examples: adding tables or columns, watch or useQuery results not updating, rows missing on a device, uploads stuck in the queue, a spinner stuck on Syncing, editing sync-config.yaml or service.yaml, running powersync CLI commands, migrating legacy sync configuration to Sync Streams, or implementing logout and account switching with disconnectAndClear."
license: MIT
compatibility: Works with any skills-compatible agent. Some references include CLI commands requiring the @powersync/cli package.
metadata:
  author: powersync
  version: "1.5.0" # x-release-please-version
  organization: PowerSync
  tags: powersync, offline-first, local-first, sync-streams, sqlite, replication, uploadData, fetchCredentials, service-config, sync-config, cloud, cli, debugging, supabase, postgres, mongodb, mysql, electric, electric-migration, watch-queries, useQuery, attachments, upload-queue, disconnectAndClear, schema, react-native, flutter, node, web, wa-sqlite
---

# PowerSync Skills

Use this skill to onboard a project onto PowerSync and to keep it healthy afterwards, without trial-and-error. Treat this as a guided workflow first and a reference library second.

**Agents: Read [AGENTS.md](AGENTS.md) before proceeding.** It contains the mandatory compliance rules and onboarding playbook. The Quick Rules below are a reminder, not a substitute. **`powersync login`** is **PowerSync Cloud only** (PAT); self-hosted does not use it.

## Terminology

- **Operator** — the human directing this agent (whose request you are fulfilling).
- **User** — an end-user of the operator's PowerSync app (JWT subjects, the row a sync stream filters by, the person calling `disconnectAndClear()`).

If a sentence is ambiguous, default to the operator interpretation. Full legend in `AGENTS.md`.

## Quick Rules

- **CLI-first.** Use the [PowerSync CLI](https://docs.powersync.com/tools/cli.md) for all operations. Do not hand-write config files. See `references/powersync-cli.md`.
- **Ask, don't assume.** Ask the operator: Cloud vs self-hosted, and which backend (Supabase, Postgres, MongoDB, MySQL, MSSQL). Do not default to Supabase.
- **Backend before frontend.** Deploy sync config and verify the service before writing app code.
- **Sync Streams for new projects.** Sync Rules are legacy.
- **Keep credentials in `.env`, never hardcoded.** Record URLs and keys in `.env` as they become available; config (`!env`) and app code read from there.
- **Default scope on existing projects: sync-config only.** Do not edit `service.yaml` or `cli.yaml` unless the operator explicitly authorized service/infra changes in this conversation.
- **Confirm the target instance before any mutating command** (`deploy`, `destroy`, `stop`, `link --create`, `pull instance`). Never deploy to an instance not authorized by the operator. Treat production as off-limits unless explicitly approved.
- **Use project memory.** If your harness supports it, persist the CLI invocation, sync-config path, authorized instance ids + environment (dev/staging/prod), and allowed scope of changes. Verify saved values still match reality before acting on them. See `AGENTS.md` § "Continuous Use & Guardrails".

## What to Load for Your Task

| Task | Start with | Load on demand |
|------|-----------|----------------|
| Supabase + PowerSync | `references/onboarding-supabase.md` | `references/supabase-auth.md`, `references/sync-config.md`, SDK files |
| Custom backend (non-Supabase) | `references/onboarding-custom.md` | `references/custom-backend.md`, `references/sync-config.md`, SDK files |
| New project setup | `references/powersync-cli.md` + `references/powersync-service.md` | `references/sync-config.md`, SDK files |
| Migrating from Electric Cloud | `references/migration-from-electric.md` | `references/sync-config.md`, SDK files |
| Self-hosting / service config | `references/powersync-service.md` + `references/powersync-cli.md` | `references/sync-config.md` |
| Terraform / IaC provisioning | `references/terraform.md` | `references/sync-config.md`, `references/supabase-auth.md` (if Supabase source) |
| Writing sync config | `references/sync-config.md` | — |
| Debugging sync issues | `references/powersync-debug.md` | — |
| Raw Tables (advanced) | `references/raw-tables.md` | — |
| Attachments | `references/attachments.md` | — |
| Architecture overview | `references/powersync-overview.md` | — |
| SQLite extensions (vector search, FTS5, custom tokenizers) | `references/sqlite-extensions.md` | — |

## SDK Reference Files

### JavaScript / TypeScript

Always load `references/sdks/powersync-js.md` for any JS/TS project, then load the applicable framework file.

| Framework | File | Load early if… |
|-----------|------|----------------|
| React / Next.js | `references/sdks/powersync-js-react.md` | Vite + React project — contains the required `vite.config.ts` setup (`optimizeDeps.exclude`, `worker.format: 'es'`) needed before installing packages |
| React Native / Expo | `references/sdks/powersync-js-react-native.md` | |
| Vue / Nuxt | `references/sdks/powersync-js-vue.md` | |
| Node.js / Electron | `references/sdks/powersync-js-node.md` | |
| TanStack | `references/sdks/powersync-js-tanstack.md` | |
| Drizzle / Kysely ORM | `references/sdks/powersync-js-orm.md` | Project uses Drizzle or Kysely |

### Other SDKs

| Platform | File |
|----------|
| Dart / Flutter | `references/sdks/powersync-dart.md` |
| .NET | `references/sdks/powersync-dotnet.md` |
| Kotlin | `references/sdks/powersync-kotlin.md` |
| Swift | `references/sdks/powersync-swift.md` |

## Key Rules to Apply Without Being Asked

- Never define the `id` column in a PowerSync table schema; it is created automatically.
- Use `column.integer` for booleans and `column.text` for ISO date strings.
- `connect()` is fire-and-forget. Use `waitForFirstSync()` if you need readiness.
- `transaction.complete()` is mandatory or the upload queue stalls permanently.
- `disconnectAndClear()` is required on logout or user switch when local data must be wiped.
- A 4xx response from `uploadData` blocks the upload queue permanently; return 2xx for validation errors.
