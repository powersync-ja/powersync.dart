---
name: powersync-js-vue
description: PowerSync Vue and Nuxt integration — composables, plugin setup, Kysely ORM, and diagnostics panel
metadata:
  tags: vue, nuxt, composables, useQuery, javascript, typescript, offline-first
---

# PowerSync Vue & Nuxt

> **Load this when** building a Vue app or Nuxt app with PowerSync. Always load `powersync-js.md` first.

## Table of Contents
- [Vue](#vue) (Plugin, Composables, Watchers)
- [Nuxt](#nuxt) (Module, Auto-imports, SSR)

Vue-specific integration for the PowerSync JavaScript SDK. Use this reference alongside `references/sdks/powersync-js.md` when building Vue apps or Nuxt apps.

| Resource | Description |
|----------|-------------|
| [Vue Composables Reference](https://docs.powersync.com/client-sdks/frameworks/vue.md) | Full Vue composables guide, consult for details beyond the inline examples. |
| [Vue SDK API Reference](https://powersync-ja.github.io/powersync-js/vue-sdk) | Full API reference for `@powersync/vue`, consult only when the inline examples don't cover your case. |
| [Nuxt Integration Guide](https://docs.powersync.com/client-sdks/frameworks/nuxt.md) | Full Nuxt setup guide. |
| [Nuxt Module API Reference](https://powersync-ja.github.io/powersync-js/nuxt-sdk) | API reference for `@powersync/nuxt`. |

## Vue

### 1. Install

```bash
# npm (v7+ installs peer dependencies automatically)
npm install @powersync/vue@latest

# pnpm (must install peer dependencies explicitly)
pnpm add @powersync/vue@latest @powersync/web@latest
```

### 2. Plugin Setup

```ts
import { createPowerSyncPlugin } from '@powersync/vue';
import { PowerSyncDatabase } from '@powersync/web';
import { AppSchema } from './AppSchema';
import { PowerSyncConnector } from './PowerSyncConnector';
import { createApp } from 'vue';
import App from './App.vue';

const db = new PowerSyncDatabase({
  database: { dbFilename: 'app.db' },
  schema: AppSchema
});

const connector = new PowerSyncConnector();
db.connect(connector);

const app = createApp(App);
app.use(createPowerSyncPlugin({ database: db }));
app.mount('#app');
```

### Composables

In a standalone Vue app, composables are imported from `@powersync/vue`. In Nuxt, all composables are auto-imported — no import statement is needed.

#### `useQuery`

Reactive query — re-renders the component automatically when underlying data changes.

```ts
import { useQuery } from '@powersync/vue'; // omit import in Nuxt

const { data: lists, isLoading, isFetching, error } = useQuery(
  'SELECT * FROM lists ORDER BY created_at DESC'
);
```

With parameters (parameters are reactive — can be a `ref` or `computed`):

```ts
const { data: todos } = useQuery(
  'SELECT * FROM todos WHERE list_id = ?',
  [listId]
);
```

Return shape: `{ data: Ref<RowType[]>, isLoading: Ref<boolean>, isFetching: Ref<boolean>, error: Ref<Error | undefined> }`.

For advanced watch query features including incremental updates and differential results, see [Live Queries / Watch Queries](https://docs.powersync.com/client-sdks/watch-queries.md).

#### `useStatus`

Reactive connectivity status. Same shape as the React `useStatus` hook — see `references/sdks/powersync-js.md` for the full status field reference.

```ts
import { useStatus } from '@powersync/vue'; // omit import in Nuxt

const status = useStatus();
// status.connected, status.hasSynced, status.lastSyncedAt, etc.
```

#### `usePowerSync`

Access the `PowerSyncDatabase` instance directly for imperative operations.

```ts
import { usePowerSync } from '@powersync/vue'; // omit import in Nuxt
import { v4 as uuid } from 'uuid';

const powersync = usePowerSync();

await powersync.value.execute(
  'INSERT INTO lists (id, created_at, name, owner_id) VALUES (?, ?, ?, ?)',
  [uuid(), new Date().toISOString(), 'My List', currentUserId]
);
```

`usePowerSync()` returns a `Ref<AbstractPowerSyncDatabase>` — access the database via `.value`.

### Setup Context Requirement

`usePowerSync`, `useQuery`, and `useStatus` all rely on Vue's `inject()` internally and must be called at the top level of a `<script setup>` block (or the synchronous `setup()` function). They must not be called inside nested functions, async functions, event handlers, or lifecycle hooks.

```vue
<script setup>
import { usePowerSync } from '@powersync/vue';

// ✅ Correct — called at the top level of setup
const powerSync = usePowerSync();

const handleClick = async () => {
  // ✅ Use the ref returned from the top-level call
  const result = await powerSync.value.getAll('SELECT * FROM lists');
  console.log(result);
};

// ❌ Wrong — usePowerSync() called inside a nested function
const handleClickBad = async () => {
  const result = await usePowerSync().value.getAll('SELECT * FROM lists');
};
</script>
```

Calling these composables outside of a setup context throws an error. If you need to access the PowerSync database outside a component (e.g. in a store or utility module), export the database instance directly instead of using the composable.

### Example Component

```vue
<script setup lang="ts">
import { usePowerSync, useQuery, useStatus } from '@powersync/vue';

const powersync = usePowerSync();
const { data: lists, isLoading } = useQuery('SELECT * FROM lists ORDER BY created_at DESC');
const status = useStatus();
</script>

<template>
  <div>
    <p>Status: {{ status.connected ? 'Connected' : 'Offline' }}</p>
    <p v-if="isLoading">Loading...</p>
    <ul v-else>
      <li v-for="list in lists" :key="list.id">{{ list.name }}</li>
    </ul>
  </div>
</template>
```

---

## Nuxt

> Alpha: `@powersync/nuxt` is currently in Alpha. APIs and behavior may change.

`@powersync/nuxt` is a Nuxt module that wraps `@powersync/vue` and re-exports all its composables. It also adds a Nuxt Devtools integration with a PowerSync diagnostics panel.

PowerSync is tailored for client-side applications. Nuxt evaluates plugins server-side unless you use the `.client.ts` suffix. The PowerSync Web SDK requires browser APIs not available in Node.js — it performs no-ops in Node.js rather than throwing errors, but no data is available during SSR. Always create your PowerSync plugin as `plugins/powersync.client.ts`.

### 1. Install

```bash
# npm (v7+ installs peer dependencies automatically)
npm install @powersync/nuxt@latest

# pnpm (must install peer dependencies explicitly)
pnpm add @powersync/nuxt@latest @powersync/vue@latest @powersync/web@latest
```

### 2. `nuxt.config.ts`

Add `@powersync/nuxt` to the `modules` array and include the required Vite configuration:

```typescript
export default defineNuxtConfig({
  modules: ['@powersync/nuxt'],
  vite: {
    optimizeDeps: {
      exclude: ['@powersync/web']
    },
    worker: {
      format: 'es'
    }
  }
});
```

### 3. Create the Plugin

Create `plugins/powersync.client.ts`. The `.client.ts` suffix ensures this only runs in the browser.

```typescript
import { NuxtPowerSyncDatabase, createPowerSyncPlugin } from '@powersync/nuxt';
import { AppSchema } from '~/powersync/AppSchema';
import { PowerSyncConnector } from '~/powersync/PowerSyncConnector';

export default defineNuxtPlugin({
  async setup(nuxtApp) {
    const db = new NuxtPowerSyncDatabase({
      database: {
        dbFilename: 'my-app.sqlite'
      },
      schema: AppSchema
    });

    const connector = new PowerSyncConnector();

    await db.init();
    await db.connect(connector);

    const plugin = createPowerSyncPlugin({ database: db });
    nuxtApp.vueApp.use(plugin);
  }
});
```

### Using Composables

All `@powersync/vue` composables (`usePowerSync`, `useQuery`, `useStatus`) are auto-imported in Nuxt — no import statement is needed in components or composables.

```vue
<script setup lang="ts">
// No imports needed — composables are auto-imported by @powersync/nuxt

const powersync = usePowerSync();
const { data: lists, isLoading } = useQuery('SELECT * FROM lists ORDER BY created_at DESC');
const status = useStatus();
</script>
```

The same [setup context requirement](#setup-context-requirement) as standalone Vue applies — call composables at the top level of `<script setup>`, not inside nested or async functions.

### Kysely ORM (Optional)

The module optionally exposes a `usePowerSyncKysely()` composable for type-safe query building.

Install the driver:

```bash
npm install @powersync/kysely-driver@latest
```

Enable it in `nuxt.config.ts`:

```typescript
export default defineNuxtConfig({
  modules: ['@powersync/nuxt'],
  powersync: {
    kysely: true
  },
  vite: {
    optimizeDeps: {
      exclude: ['@powersync/web']
    },
    worker: {
      format: 'es'
    }
  }
});
```

Use in components — `usePowerSyncKysely` is auto-imported. Import only your schema's `Database` type for full type safety:

```typescript
import { type Database } from '~/powersync/AppSchema';

const db = usePowerSyncKysely<Database>();

const lists = await db.selectFrom('lists').selectAll().execute();
```

### Diagnostics Panel

`@powersync/nuxt` includes a PowerSync diagnostics panel that shows sync status, local data, bucket contents, config, and logs. Must be explicitly enabled.

Enable in `nuxt.config.ts`:

```typescript
export default defineNuxtConfig({
  modules: ['@powersync/nuxt'],
  powersync: {
    useDiagnostics: true
  },
  vite: {
    optimizeDeps: {
      exclude: ['@powersync/web']
    },
    worker: {
      format: 'es'
    }
  }
});
```

When `useDiagnostics: true` is set, `NuxtPowerSyncDatabase` automatically extends the schema with the diagnostics schema, sets up recording and logging, and stores the connector internally. No changes to the plugin file are needed.

Access the inspector:
- Nuxt Devtools: open browser Devtools and look for the PowerSync tab
- Direct URL: navigate to `http://localhost:3000/__powersync-inspector`

### Known Issues

#### Tailwind CSS conflict

PowerSync Inspector uses `unocss` as a transitive dependency, which conflicts with Tailwind CSS. If you use Tailwind, add the following to `nuxt.config.ts`:

```typescript
export default defineNuxtConfig({
  unocss: {
    autoImport: false
  }
});
```
