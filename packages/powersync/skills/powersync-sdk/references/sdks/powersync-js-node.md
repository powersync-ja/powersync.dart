---
name: powersync-js-node
description: PowerSync Node.js and Electron integration — CLI setup, background sync, ETL pipelines, and Electron renderer/main process split
metadata:
  tags: nodejs, electron, cli, javascript, typescript, better-sqlite3, offline-first
---

# PowerSync Node.js & Electron

> **Load this when** building a Node.js CLI tool, background sync process, ETL pipeline, or Electron desktop app. Always load `powersync-js.md` first.

Node.js-specific integration for the PowerSync JavaScript SDK. Use this reference alongside `references/sdks/powersync-js.md` when building Node.js CLI tools, background sync processes, ETL pipelines, or Electron desktop apps.

| Resource | Description |
|----------|-------------|
| [Node.js SDK Reference](https://docs.powersync.com/client-sdks/reference/node.md) | Full SDK documentation for Node.js, consult for details beyond the inline examples. |
| [Node SDK API Reference](https://powersync-ja.github.io/powersync-js/node-sdk) | Full API reference for `@powersync/node`, consult only when the inline examples don't cover your case. |

## Node.js

### 1. Install

```bash
npm install @powersync/node@latest
npm install better-sqlite3   # required peer dependency
```

TypeScript types for `better-sqlite3`:

```bash
npm install --save-dev @types/better-sqlite3
```

### Key Differences from the Web SDK

| Aspect | `@powersync/web` | `@powersync/node` |
|--------|-----------------|-------------------|
| SQLite runtime | WebAssembly (wa-sqlite) | Native (`better-sqlite3`) |
| Web Workers | Yes — DB runs in a worker by default | No — runs synchronously in the main thread |
| Multi-tab sync | Yes — shared sync worker across browser tabs | No |
| UI framework hooks | `@powersync/react`, `@powersync/vue` | None — use imperative API |
| Environment | Browser | Node.js 18+ |

### 2. Setup

```ts
import { PowerSyncDatabase } from '@powersync/node';
import { AppSchema } from './AppSchema';
import { PowerSyncConnector } from './PowerSyncConnector';

const db = new PowerSyncDatabase({
  schema: AppSchema,
  database: {
    dbFilename: 'app.db'
  }
});

const connector = new PowerSyncConnector();
await db.connect(connector);
```

`connect()` behaves the same as the web SDK — it starts the sync stream in the background. Use `db.waitForFirstSync()` to wait for data before proceeding.

### Querying

No UI hooks are available in Node.js. Use the imperative API from `references/sdks/powersync-js.md` directly:

```ts
// One-time queries
const lists = await db.getAll('SELECT * FROM lists WHERE owner_id = ?', [userId]);
const list = await db.getOptional('SELECT * FROM lists WHERE id = ?', [id]);

// Watch for changes (async generator)
for await (const result of db.watchWithAsyncGenerator('SELECT * FROM lists')) {
  console.log('Lists updated:', result.rows._array);
}

// Writes
await db.execute('INSERT INTO lists (id, name) VALUES (uuid(), ?)', ['My List']);
await db.writeTransaction(async (tx) => {
  await tx.execute('DELETE FROM lists WHERE id = ?', [listId]);
  await tx.execute('DELETE FROM todos WHERE list_id = ?', [listId]);
});
```

### Use Cases

- CLI tools: Sync data from a PowerSync service for offline-capable scripts
- Background sync jobs: Keep a local SQLite database up to date with server data for reporting or ETL
- Server-side scripts: Read/write to a local PowerSync-managed SQLite database without a browser

### Sync Status

The same `db.currentStatus` and `db.registerListener` API applies:

```ts
db.registerListener({
  statusChanged: (status) => {
    console.log('Connected:', status.connected, '| Last synced:', status.lastSyncedAt);
  }
});
```

---

## Electron

Electron apps have two distinct environments — the renderer process (a Chromium browser window) and the main process (Node.js). PowerSync has a different SDK for each.

### Architecture

```
Electron App
├── Renderer Process (Chromium)
│   └── Use @powersync/web + @powersync/react or @powersync/vue
│       → See references/sdks/powersync-js-react.md or references/sdks/powersync-js-vue.md
│
└── Main Process (Node.js)
    └── Use @powersync/node + better-sqlite3
        → Use imperative API — no UI hooks available
```

### Renderer Process

The renderer process is a full browser environment. Set it up exactly like any other web app:

```bash
npm install @powersync/web@latest @journeyapps/wa-sqlite@latest @powersync/react@latest
```

Use `PowerSyncContext.Provider` and `useQuery`/`useStatus` hooks as documented in `references/sdks/powersync-js-react.md`. The Web-Specific Options section in `references/sdks/powersync-js.md` (VFS options, multi-tab, `debugMode`) also applies to the renderer process.

### Main Process

The main process runs Node.js with no DOM. Use `@powersync/node`:

```bash
npm install @powersync/node@latest better-sqlite3
```

```ts
// main/db.ts
import { PowerSyncDatabase } from '@powersync/node';
import { AppSchema } from './AppSchema';
import { PowerSyncConnector } from './PowerSyncConnector';

export const db = new PowerSyncDatabase({
  schema: AppSchema,
  database: { dbFilename: 'app.db' }
});

export async function initDb() {
  const connector = new PowerSyncConnector();
  await db.connect(connector);
  await db.waitForFirstSync();
}
```

### IPC Pattern

If you sync data in the main process and need to expose it to the renderer, use Electron's IPC:

```ts
// main/ipcHandlers.ts
import { ipcMain } from 'electron';
import { db } from './db';

ipcMain.handle('powersync:query', async (_event, sql: string, params: any[]) => {
  return db.getAll(sql, params);
});
```

```ts
// renderer — via preload bridge
const lists = await window.electron.invoke('powersync:query', 'SELECT * FROM lists', []);
```

However, the more common pattern is to use `@powersync/web` in the renderer and maintain a separate sync connection there — this keeps the data layer entirely in the renderer process and avoids IPC overhead.

## Common Pitfalls

### Using `@powersync/web` in Node.js

`@powersync/web` requires browser APIs (`SharedWorker`, `indexedDB`, WebAssembly with browser globals) that are not available in Node.js. Always use `@powersync/node` for the main process or any non-browser Node.js environment.

### Missing `better-sqlite3` native build

`better-sqlite3` is a native module that must be compiled for the target platform. In Electron, it must be rebuilt for Electron's Node.js version using `electron-rebuild` or `@electron/rebuild`:

```bash
npx @electron/rebuild -f -w better-sqlite3
```

Run this after any Electron version upgrade.

### Encryption Key Escaping

If the encryption key passed to `pragma key` may contain single quotes, use `replaceAll` to escape them, not `replace`. The `replace` method only replaces the first occurrence; a key with multiple single quotes will be incorrectly escaped, causing a decryption failure or SQL syntax error.

```ts
initializeConnection: async (db) => {
  if (encryptionKey.length) {
    const escapedKey = encryptionKey.replaceAll("'", "''");
    await db.execute(`pragma key = '${escapedKey}'`);
  }
}
```
