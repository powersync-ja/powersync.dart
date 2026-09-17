---
name: powersync-js-react
description: PowerSync React and Next.js integration — PowerSyncContext, useSuspenseQuery, useQuery, sync stream hooks, and Next.js/Vite setup
metadata:
  tags: react, nextjs, vite, hooks, useSuspenseQuery, useQuery, PowerSyncContext, javascript, typescript, isFetching, disconnectAndClear
---

# PowerSync React & Next.js

> **Load this when** building a React web app, Next.js app, or any Vite + React project. Load **before** package install for Vite projects — contains the required `vite.config.ts` setup. Always load `powersync-js.md` first.

## Table of Contents
- [Provider Setup](#provider-setup)
- [useSuspenseQuery](#usesuspensequery)
- [Sync Stream Hooks](#sync-stream-hooks)
- [Next.js Setup](#nextjs-setup)
- [Vite Setup](#vite-setup)
- [Common Pitfalls](#common-pitfalls)

React-specific integration for the PowerSync JavaScript SDK. Use this reference alongside `references/sdks/powersync-js.md` when building React web apps, Next.js apps, or when using the React hooks from `@powersync/react` or `@powersync/react-native`.

| Resource | Description |
|----------|-------------|
| [React Integration Guide](https://docs.powersync.com/client-sdks/frameworks/react.md) | Full React setup guide, consult for details beyond the inline examples. |
| [Next.js Integration Guide](https://docs.powersync.com/client-sdks/frameworks/next-js.md) | Full Next.js setup guide, consult for details beyond the inline examples. |
| [React SDK API Reference](https://powersync-ja.github.io/powersync-js/react-sdk) | Full API reference for `@powersync/react`, consult only when the inline examples don't cover your case. |

## Provider Setup

```tsx
import { PowerSyncContext } from '@powersync/react'; // or @powersync/react-native

export function App() {
  return (
    <PowerSyncContext.Provider value={db}>
      <YourApp />
    </PowerSyncContext.Provider>
  );
}
```

All hooks (`useQuery`, `useSuspenseQuery`, `useStatus`) read from this context via `usePowerSync()`. If the provider is missing, `useQuery` returns `{ isLoading: false, error: Error('PowerSync not configured.') }`, and `useSuspenseQuery` throws.

## useSuspenseQuery

```ts
useSuspenseQuery<RowType>(
  query: string | CompilableQuery<RowType>,
  parameters?: any[],
  options?: { rowComparator?, reportFetching?, throttleMs?, runQueryOnce? }
): { data, isFetching }  // no isLoading — always has data when it returns
```

Must be used inside a `<Suspense>` boundary. Throws an error boundary-catchable error if the query errors. Always pair with an `<ErrorBoundary>`:

```tsx
<ErrorBoundary fallback={<ErrorUI />}>
  <Suspense fallback={<Loading />}>
    <DataComponent />  {/* calls useSuspenseQuery */}
  </Suspense>
</ErrorBoundary>
```

`useSuspenseQuery` uses a `QueryStore` (one per `PowerSyncDatabase` instance, stored in a `WeakMap`). The store caches `WatchedQuery` instances keyed by:

```
"${sql} -- ${JSON.stringify(params)} -- ${JSON.stringify(options)}"
```

A query is evicted (closed) when all listeners are removed. `useSuspenseQuery` and `useQuery` with the same SQL/params/options share the same underlying `WatchedQuery`.

## Sync Stream Hooks

React hooks for subscribing to named Sync Streams. Requires the PowerSync service to be configured with Sync Streams (edition 3 config). See [Sync Streams Overview](https://docs.powersync.com/sync/streams/overview.md) and [Client-Side Usage](https://docs.powersync.com/sync/streams/client-usage.md#react-hooks) for more information.

```tsx
import { useSyncStream, useSuspenseSyncStream } from '@powersync/react';

// Non-suspense — returns null while subscription is being established
function ListsScreen() {
  const streamStatus = useSyncStream({
    name: 'lists',
    parameters: { userId: currentUser.id },
    priority: 1,  // optional, 0-3
    ttl: 3600,    // optional, seconds to keep alive after unsubscribe
  });

  if (!streamStatus) return <Loading />;  // subscription not yet ready
  if (!streamStatus.subscription.hasSynced) return <Loading />;

  return <ListsComponent />;
}

// Suspense version — never returns null, suspends instead
function ListsScreen() {
  const streamStatus = useSuspenseSyncStream({
    name: 'lists',
    parameters: { userId: currentUser.id },
  });
  // streamStatus.subscription.hasSynced is guaranteed true here
  return <ListsComponent />;
}
```

Automatic cleanup: Both hooks unsubscribe when the component unmounts. The TTL keeps data active for the specified duration after unsubscribe.

### SyncStreamStatus Fields

```ts
interface SyncStreamStatus {
  subscription: {
    name: string;
    parameters: Record<string, any> | null;
    active: boolean;         // currently receiving data
    isDefault: boolean;      // was configured as a default stream on the server
    hasExplicitSubscription: boolean;
    expiresAt: Date | null;  // when TTL expires
    hasSynced: boolean;      // has completed at least one full sync
    lastSyncedAt: Date | null;
  };
  progress: {
    downloadedFraction: number;  // 0.0-1.0
    downloadedOperations: number;
    totalOperations: number;
  } | null;
  priority: number | null;
}
```

## Next.js Setup

PowerSync is tailored for client-side applications. Next.js evaluates code in a Node.js runtime during SSR — the PowerSync Web SDK requires browser APIs not available in Node.js. It performs no-ops in Node.js rather than throwing errors, but no data is available during SSR. Always isolate PowerSync to client-side code.

### Install

```bash
npm install @powersync/web@latest @powersync/react@latest
```

### Copy Worker Assets (Turbopack)

Turbopack doesn't support dynamic imports of workers yet. Add a `postinstall` script to copy pre-bundled worker files to your public directory:

```json
{
  "scripts": {
    "postinstall": "powersync-web copy-assets -o public"
  }
}
```

Run it once after install, then add to `.gitignore`:

```
public/@powersync/*
```

### `next.config.ts` — Turbopack (Next.js 16+)

```typescript
module.exports = {
  images: {
    disableStaticImages: true
  },
  turbopack: {}
};
```

### `next.config.ts` — Webpack (legacy, pre-Next.js 16)

```typescript
module.exports = {
  webpack: (config, { isServer }) => {
    config.experiments = {
      ...config.experiments,
      asyncWebAssembly: true,
      topLevelAwait: true,
    };

    if (!isServer) {
      config.module.rules.push({
        test: /\.wasm$/,
        type: 'asset/resource',
      });
    }

    return config;
  }
};
```

### SystemProvider

Create a client-only provider component. The `disableSSRWarning: true` flag suppresses the Node.js no-op warning. The pre-bundled worker paths reference the files copied by `powersync-web copy-assets`.

```tsx
// components/providers/SystemProvider.tsx
'use client';

import { AppSchema } from '@/lib/powersync/AppSchema';
import { BackendConnector } from '@/lib/powersync/BackendConnector';
import { PowerSyncContext } from '@powersync/react';
import { PowerSyncDatabase, WASQLiteOpenFactory, createBaseLogger, LogLevel } from '@powersync/web';
import React, { Suspense } from 'react';

const factory = new WASQLiteOpenFactory({
  dbFilename: 'powersync.db',
  // Pre-bundled worker — required for Turbopack
  worker: '/@powersync/worker/WASQLiteDB.umd.js'
});

export const db = new PowerSyncDatabase({
  database: factory,
  schema: AppSchema,
  flags: {
    disableSSRWarning: true
  },
  sync: {
    worker: '/@powersync/worker/SharedSyncImplementation.umd.js'
  }
});

const connector = new BackendConnector();
db.connect(connector);

export const SystemProvider = ({ children }: { children: React.ReactNode }) => {
  return (
    <Suspense>
      <PowerSyncContext.Provider value={db}>{children}</PowerSyncContext.Provider>
    </Suspense>
  );
};
```

### Update `layout.tsx`

```tsx
// app/layout.tsx
'use client';

import { SystemProvider } from '@/app/components/providers/SystemProvider';

export default function RootLayout({ children }: { children: React.ReactNode }) {
  return (
    <html lang="en">
      <body>
        <SystemProvider>{children}</SystemProvider>
      </body>
    </html>
  );
}
```

### Using PowerSync in Pages

```tsx
// app/page.tsx
'use client';

import { useQuery, useStatus, usePowerSync } from '@powersync/react';

export default function Page() {
  const powersync = usePowerSync();
  const status = useStatus();
  const { data: lists, isLoading } = useQuery('SELECT * FROM lists');

  return (
    <ul>
      {lists.map(list => <li key={list.id}>{list.name}</li>)}
    </ul>
  );
}
```

All components that use PowerSync hooks must have `'use client'` at the top. PowerSync hooks are not compatible with React Server Components.

## Vite Setup

Vite requires `vite-plugin-wasm` + `vite-plugin-top-level-await` to handle the WASM SQLite engine.

```bash
npm install -D vite-plugin-wasm vite-plugin-top-level-await
```

```ts
// vite.config.ts
import wasm from 'vite-plugin-wasm'
import topLevelAwait from 'vite-plugin-top-level-await'

export default defineConfig({
  plugins: [react(), wasm(), topLevelAwait()],
  optimizeDeps: {
    exclude: ['@journeyapps/wa-sqlite', '@powersync/web'],
  },
  worker: {
    format: 'es',
    plugins: () => [wasm(), topLevelAwait()],
  },
})
```

> **Do NOT** add `optimizeDeps: { include: ['@powersync/web > js-logger'] }` — this dependency path does not exist in current SDK versions and causes build warnings. The `exclude` configuration above is sufficient.

## Common Pitfalls

### React Strict Mode destroys PowerSyncDatabase in useEffect

In development, React Strict Mode unmounts and remounts every component. If you create a `PowerSyncDatabase` inside a `useEffect` cleanup/setup cycle, the first mount's cleanup releases the shared-worker DB proxy before the second mount can use it — the database connection silently breaks.

```tsx
// WRONG — Strict Mode will destroy this on the dev double-mount
function App() {
  const [db, setDb] = useState<PowerSyncDatabase | null>(null);
  useEffect(() => {
    const database = new PowerSyncDatabase({ schema, database: { dbFilename: 'app.db' } });
    database.connect(connector);
    setDb(database);
    return () => { database.close(); }; // Kills the DB on Strict Mode re-mount
  }, []);
  // ...
}

// CORRECT — create once at module scope (or use a stable singleton)
const db = new PowerSyncDatabase({ schema, database: { dbFilename: 'app.db' } });
db.connect(connector);

function App() {
  return (
    <PowerSyncContext.Provider value={db}>
      <YourApp />
    </PowerSyncContext.Provider>
  );
}
```

Keep the DB instance stable across transient remounts. Only call `db.close()` when the app is truly done with it (e.g. on logout with `disconnectAndClear()`). Disabling `enableMultiTabs` can mask the symptom temporarily but does not fix the root cause.

### Suspense requires ErrorBoundary

`useSuspenseQuery` throws query errors upward — they go to the nearest `<ErrorBoundary>`, not `<Suspense>`. Without an ErrorBoundary, query errors crash the component tree silently.

```tsx
<ErrorBoundary fallback={<ErrorUI />}>
  <Suspense fallback={<Loading />}>
    <DataComponent />
  </Suspense>
</ErrorBoundary>
```

### Next.js: forgetting `'use client'`

Any component that calls `usePowerSync`, `useQuery`, `useStatus`, or `useSuspenseQuery` must be a Client Component. Forgetting `'use client'` causes a build error or a runtime error about hooks in Server Components.

### Next.js: awaiting `db.connect()` at module scope

`connect()` is fire-and-forget. Calling `await db.connect(connector)` at module scope in a Next.js file will block the module evaluation. Call `db.connect(connector)` without `await` in your provider, then use `db.waitForFirstSync()` if you need to gate rendering on data availability.

### Never flip the context database between null and non-null

`useQuery` takes an early return path (calling fewer hooks) when `usePowerSync()` returns null. A provider that withholds the database on some renders and supplies it on others for the same mounted tree changes the hook count between renders and crashes with "Rendered fewer hooks than expected".

If readiness genuinely must close (for example, the database is being torn down and replaced), remount the consuming subtree with a `key` change instead of setting the context value to null. Better: design the provider so readiness never closes for non-changes, such as an auth provider re-confirming the same user (see the next pitfall).

### Auth confirmation is not a schema change

Apps that support both signed-out (local-only) and signed-in (synced) use need a small orchestration layer around sign-in and sign-out. A recipe that works:

- Keep durable per-database markers: the owner user ID and whether the database is in local or synced mode.
- On boot, open reads immediately based on those markers, before the auth provider resolves.
- When the auth provider then confirms the same identity, confirm in place: do not tear down readers, take exclusive locks, or put `connect()` on the read path.
- Reserve the destructive transition (`disconnectAndClear()`, reopen, reconnect) for actual identity changes: sign-out, or a different user signing in.

Treating a same-identity confirmation as a destructive transition shows up as content appearing on a hard reload, being yanked away for seconds while the app rebuilds, then reappearing. Confirming in place keeps content on screen throughout.

### `@powersync/react` 2.0.x: `isFetching` pinned true behind a closed stream gate

In `@powersync/react` 2.0.0, a query change while a `streams: [{ waitForStream: true }]` gate is closed leaves `isFetching` pinned true forever: the `useWatchedQuery` effect cleanup disposes the pending-update listener without clearing its ref, so the update that would clear `isFetching` never lands. Observed in 2.0.0 and still present in 2.0.1.

Mitigations:

- Before relying on `isFetching` behind a stream gate, verify that the installed version's `useWatchedQuery` effect cleanup nulls the pending-update listener ref.
- Or avoid gating queries through the `streams` `waitForStream` option, and gate on sync status externally (for example, on the stream subscription's `hasSynced`) instead.

If you patch this locally: a patch keyed to an exact package version in a lockfile silently stops applying when the resolved version drifts. Pin the package version, or make the patch tooling fail loudly on a version mismatch.
