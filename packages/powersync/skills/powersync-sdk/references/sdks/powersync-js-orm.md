---
name: powersync-js-orm
description: Drizzle and Kysely ORM integration with PowerSync JavaScript SDK — type-safe queries, schema definition, and CompilableQuery usage
metadata:
  tags: javascript, typescript, drizzle, kysely, orm, powersync
---

> **Load this when** the project uses Drizzle or Kysely ORM with PowerSync. Always load `powersync-js.md` first.

# Drizzle & Kysely ORM Integration

PowerSync provides official drivers for both Drizzle and Kysely. These let you write type-safe queries that work with PowerSync's reactive hooks (`useQuery`, `useSuspenseQuery`) via the `CompilableQuery` interface.

| ORM | Package | Docs |
|-----|---------|------|
| Drizzle | `@powersync/drizzle-driver` | [Drizzle Setup](https://docs.powersync.com/client-sdks/orms/javascript-web/drizzle.md) |
| Kysely | `@powersync/kysely-driver` | [Kysely Setup](https://docs.powersync.com/client-sdks/orms/javascript-web/kysely.md) |

## Drizzle

```bash
npm install @powersync/drizzle-driver@latest drizzle-orm
```

```ts
import { drizzle } from '@powersync/drizzle-driver';
import { sqliteTable, text, integer } from 'drizzle-orm/sqlite-core';
import { eq } from 'drizzle-orm';

// Define Drizzle schema — separate from the PowerSync schema
export const todos = sqliteTable('todos', {
  id: text('id').primaryKey(),
  description: text('description').notNull(),
  completed: integer('completed').notNull().default(0),
  listId: text('list_id')
});

// Create Drizzle instance from the PowerSync database
const drizzleDb = drizzle(db);

// Type-safe queries
const activeTodos = await drizzleDb
  .select()
  .from(todos)
  .where(eq(todos.completed, 0));
```

### Drizzle with useQuery

Drizzle queries implement `CompilableQuery`, so they work directly with PowerSync hooks:

```ts
const query = drizzleDb.select().from(todos).where(eq(todos.completed, 0));
const { data } = useQuery(query);
```

## Kysely

```bash
npm install @powersync/kysely-driver@latest kysely
```

```ts
import { wrapPowerSyncWithKysely } from '@powersync/kysely-driver';

// Define types for Kysely
interface Database {
  todos: { id: string; description: string; completed: number; list_id: string };
  lists: { id: string; name: string; owner_id: string };
}

// Create Kysely instance from the PowerSync database
const kyselyDb = wrapPowerSyncWithKysely<Database>(db);

// Type-safe queries
const activeTodos = await kyselyDb
  .selectFrom('todos')
  .selectAll()
  .where('completed', '=', 0)
  .execute();
```

### Kysely with useQuery

```ts
const query = kyselyDb.selectFrom('todos').selectAll().where('completed', '=', 0);
const { data } = useQuery(query);
```

## Both schemas are needed

You need **two** schemas when using an ORM:

1. **PowerSync schema** (`new Schema(...)`) — defines what data syncs. Required.
2. **ORM schema** (Drizzle `sqliteTable` or Kysely interface) — provides type safety for queries. Optional but recommended.

These must stay in sync — if you add a column to the PowerSync schema, add it to the ORM schema too.
