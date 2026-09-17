---
name: powersync-js-tanstack
description: PowerSync TanStack integrations — TanStack Query caching, TanStack DB collections, optimistic mutations, and schema validation
metadata:
  tags: tanstack, tanstack-query, tanstack-db, react, javascript, typescript, offline-first
---

# PowerSync TanStack Integrations

> **Load this when** using TanStack Query (React) or TanStack DB (multi-framework) with PowerSync. Always load `powersync-js.md` first.

TanStack-specific integrations for the PowerSync JavaScript SDK. Use this reference alongside `references/sdks/powersync-js.md` when using TanStack Query (React) or TanStack DB (multi-framework) with PowerSync.

| Resource | Description |
|----------|-------------|
| [TanStack Query & TanStack DB](https://docs.powersync.com/client-sdks/frameworks/tanstack.md) | Full TanStack integrations guide, consult for details beyond the inline examples. |
| [TanStack React Query API Reference](https://powersync-ja.github.io/powersync-js/tanstack-react-query-sdk) | Full API reference for `@powersync/tanstack-react-query`, consult only when the inline examples don't cover your case. |
| [PowerSync Collection — TanStack DB Docs](https://tanstack.com/db/latest/docs/collections/powersync-collection) | Full TanStack DB collection reference. |
| [TanStack DB API Reference](https://tanstack.com/db/latest/docs/reference/powersync-db-collection/index) | TanStack DB collection API reference. |

---

## TanStack Query

`@powersync/tanstack-react-query` wraps TanStack Query's `useQuery` and `useSuspenseQuery` hooks, bringing TanStack's advanced async state management to PowerSync web and React Native applications.

Use TanStack Query when you need:
- Query caching by key — subsequent instances of the same query don't refire
- Flicker mitigation on navigation — stale cached data shows instantly while fresh data loads
- Pagination support via TanStack's built-in paginated query patterns
- React Suspense with navigation blocking via `v7_startTransition`

Use `@powersync/react` hooks (from `references/sdks/powersync-js-react.md`) when:
- You don't need TanStack's query cache
- You want a simpler API with fewer dependencies

### Install

```bash
npm install @powersync/tanstack-react-query@latest
```

TanStack Query also requires its core peer:

```bash
npm install @tanstack/react-query
```

### Usage

```tsx
import { useQuery, useSuspenseQuery } from '@powersync/tanstack-react-query';

// Basic reactive query with TanStack loading/error states
function ListsScreen() {
  const { data: lists, isLoading, error } = useQuery({
    queryKey: ['lists'],
    query: 'SELECT * FROM lists ORDER BY created_at DESC'
  });

  if (isLoading) return <Loading />;
  if (error) return <Error message={error.message} />;
  return <ul>{lists.map(l => <li key={l.id}>{l.name}</li>)}</ul>;
}

// Suspense version — use with a <Suspense> boundary
function ListsScreen() {
  const { data: lists } = useSuspenseQuery({
    queryKey: ['lists'],
    query: 'SELECT * FROM lists ORDER BY created_at DESC'
  });
  return <ul>{lists.map(l => <li key={l.id}>{l.name}</li>)}</ul>;
}
```

For full usage examples and configuration options, see the [package README](https://www.npmjs.com/package/@powersync/tanstack-react-query).

### Flicker Mitigation

When navigating to or refreshing a page, a brief UI flicker (10–50ms) can occur as queries rerun. TanStack Query addresses this:

- First load: use `isLoading` / a Suspense fallback
- Subsequent loads: TanStack's query cache serves stale data instantly, then updates in the background — no flicker
- Block navigation: combine `useSuspenseQuery` with `<Suspense>` and React Router's [`v7_startTransition`](https://reactrouter.com/en/main/upgrading/future#v7_starttransition) flag to ensure page B is fully loaded before navigating away from page A

---

## TanStack DB

> Alpha: The PowerSync TanStack DB collection is currently in an [Alpha](https://docs.powersync.com/resources/feature-status.md) release.

`@tanstack/powersync-db-collection` lets you use TanStack DB collections backed by PowerSync. In-memory collections stay in sync with PowerSync's SQLite database, providing offline-first reactive data with optimistic mutations.

TanStack DB is different from TanStack Query: TanStack DB uses differential data flow for in-memory queries that update incrementally, rather than re-running full SQL queries. It's more suitable for complex, highly interactive UIs that need cross-collection joins and optimistic updates.

Use TanStack DB when:
- Mutations need to feel synchronous — TanStack DB applies optimistic state in-memory immediately; PowerSync's `execute()` is async, which is fast but not instantaneous
- Your app renders many simultaneous live queries — PowerSync live queries each hold a SQLite connection from a bounded pool; if many views watch queries at once, that pool becomes a snappiness bottleneck; TanStack DB's in-memory queries bypass it entirely
- You have complex dependent queries that benefit from differential invalidation — PowerSync re-runs the full SQL query and diffs results on every table change; TanStack DB invalidates only the queries whose specific inputs changed
- You need to join a PowerSync (offline) collection with a non-PowerSync TanStack DB collection (e.g. an online store)

Use plain PowerSync (`.watch()` / `usePowerSyncQuery`) when:
- Async SQLite write latency is acceptable for your use case
- Your app has a modest number of simultaneous live queries
- Your queries are simple and don't benefit from differential invalidation
- You are not mixing offline and online collections

### Install

```bash
# Web
npm install @tanstack/powersync-db-collection@latest @powersync/web@latest

# React Native
npm install @tanstack/powersync-db-collection@latest @powersync/react-native@latest
```

Also install a TanStack DB framework adapter for your UI framework:

```bash
npm install @tanstack/react-db    # React
npm install @tanstack/vue-db      # Vue
npm install @tanstack/solid-db    # Solid
npm install @tanstack/svelte-db   # Svelte
npm install @tanstack/angular-db  # Angular
```

### Quick Start

```ts
import { Schema, Table, column } from '@powersync/web';
import { PowerSyncDatabase } from '@powersync/web';
import { createCollection } from '@tanstack/react-db';
import { powerSyncCollectionOptions } from '@tanstack/powersync-db-collection';

const APP_SCHEMA = new Schema({
  documents: new Table({
    name: column.text,
    author: column.text,
    created_at: column.text,
    archived: column.integer
  })
});

const db = new PowerSyncDatabase({
  database: { dbFilename: 'app.sqlite' },
  schema: APP_SCHEMA
});

// Optional: db.connect(connector) for backend sync

// Create a collection — types are inferred from the table definition
const documentsCollection = createCollection(
  powerSyncCollectionOptions({
    database: db,
    table: APP_SCHEMA.props.documents
  })
);
```

### Features

- Differential in-memory queries — live queries update incrementally instead of re-running entire SQL queries; stays fast even for complex queries across multiple collections
- Reactive data flow — components re-render only when their specific data changes
- Optimistic mutations — mutations apply to local state immediately; TanStack DB keeps optimistic state on top of synced data and rolls back automatically if the server request fails
- Cross-collection queries — live queries can join across collections, including mixing PowerSync collections with other TanStack DB collections
- Schema validation and rich types — use Zod (or any schema library) to validate mutations and transform SQLite types into rich JavaScript types (`Date`, boolean, JSON); supports separate deserialization schemas for synced vs. written data
- Metadata tracking — attach custom metadata to insert/update/delete operations; PowerSync persists it and exposes it in `CrudEntry.metadata` during `uploadData`
- Advanced transactions — batch multiple operations with `PowerSyncTransactor` and `createTransaction`; control commit timing and wait for persistence

### Configuration Options

`powerSyncCollectionOptions` accepts:
- `database` — the `PowerSyncDatabase` instance
- `table` — a table from your `Schema.props`
- `schema` — optional Zod (or compatible) schema for mutation validation
- `deserializationSchema` — optional separate schema for deserializing synced data
- `serializer` — optional custom serializer
- `onDeserializationError` — callback for deserialization errors
- `syncBatchSize` — number of rows to process per sync batch

See [PowerSync Collection — Configuration Options](https://tanstack.com/db/latest/docs/collections/powersync-collection#4-create-a-tanstack-db-collection) for full details.

## Common Pitfalls

### Version misalignment between TanStack packages

Type conflicts between `@powersync/common`, `@tanstack/db`, and `@tanstack/powersync-db-collection` often occur when multiple versions of the same package are installed as transitive dependencies. Check alignment:

```bash
npm ls @powersync/common
npm ls @tanstack/react-db @tanstack/powersync-db-collection @tanstack/db
```

If multiple versions appear, delete `node_modules` and the lock file, then reinstall. See also `references/powersync-debug.md` for the full debugging guidance.

### Don't mix TanStack DB collections and direct `db.execute()` without accounting for optimistic state

TanStack DB collections maintain their own in-memory optimistic state on top of the SQLite database. If you write to SQLite directly via `db.execute()` while a collection has pending optimistic mutations for the same rows, the collection's view of the data may temporarily diverge until the optimistic state is reconciled. Prefer writing through the collection's mutation API when the collection is active.
