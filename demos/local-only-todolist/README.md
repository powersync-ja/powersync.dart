# PowerSync + Supabase Flutter Todo List App: Local-Only to Sync Mode Demo

This demo app is an extension of the [Supabase Todo List App](../supabase-todolist/README.md) and demonstrates using the PowerSync Flutter client SDK to persist data locally without syncing, for users to use the app without having to register or sign in. It then demonstrates syncing this data to Supabase once the user registers at a later stage.

The recommended flow through this demo is:
1. Run the app in local-only mode and create data. Notice how data persists even when closing and reopening the app.
2. Enable user registration and sign in to the app.
3. Notice how previously created data now seamlessly syncs with Supabase.

For an overview of the mechanics behind this, see [the explanation further below](#how-this-works).

# Run the app in local-only mode

Ensure you have [melos](https://melos.invertase.dev/~melos-latest/getting-started) installed.

1. `cd demos/local-only-todolist`
2. `melos prepare`
3. `flutter run`

Create some data and notice how the data persists after a refresh or reopening the app.

It is expected that users cannot register or sign in at this stage. This is because Supabase and PowerSync credentials have not been been configured yet -- there is a hardcoded check in `main.dart` for this. We'll get to this next.

# Enable user registration and sign in

Create Supabase and PowerSync projects, and add their credentials to `lib/app_config.dart` to enable user registration and sign in.

## Set up your Supabase project

Detailed instructions for integrating PowerSync with Supabase can be found in [the integration guide](https://docs.powersync.com/integration-guides/supabase). Below are the main steps required to get this demo running.

Create a new Supabase project, and paste an run the contents of [database.sql](./database.sql) in the Supabase SQL editor.

It does the following:

1. Create `lists` and `todos` tables.
2. Create a publication called `powersync` for `lists` and `todos`.
3. Enable row level security, allowing users to only view and edit their own data.
4. Create a trigger to populate some sample data when an user registers.

## Configure your PowerSync Instance

Create a new PowerSync instance, connecting to the database of the Supabase project.

Then deploy the following sync rules:

```yaml
bucket_definitions:
  user_lists:
    # Separate bucket per todo list
    parameters: select id as list_id from lists where owner_id = request.user_id()
    data:
      - select * from lists where id = bucket.list_id
      - select * from todos where list_id = bucket.list_id
```

## Configure the app

Insert the credentials of your Supabase and PowerSync projects into `lib/app_config.dart`.

## Sign in to the app

Reload the app and sign up or sign in. Once successfully signed in, existing and new data should seamlessly sync with Supabase.


# How this works

This app uses [local-only](https://pub.dev/documentation/powersync/latest/powersync/Table/Table.localOnly.html) tables to persist data until the user has registered or signed in. Local-only tables do not log updates in an upload queue, avoiding any overhead or growth in database size.

Once the user registers, the data is moved over to synced tables, at which point the data would be placed in the upload queue and will start syncing.

## Naive implementation

A barebones way to achieve the above is to store and query data from local-only tables before registration, copy this data to each corresponding synced table after registration and then store and query from the synced tables. This would look as follows:

![diagram-0](./assets/local-only-readme-0.png)

The downside to this approach is that app queries would need to continuously differentiate between the two tables based on whether the user signed in or not.

## Recommended implementation

To keep app queries consistent between the two states, we utilize the [viewName](https://pub.dev/documentation/powersync/latest/powersync/Table/viewName.html) property, which allows overriding the default name of the view that is used in queries. 

This looks as follows in the local-only state:

![diagram-1](./assets/local-only-readme-1.png)

The local-only tables (`local_lists` and `local_todos`) have their view names overriden to `listsAlias` and `todosAlias`, and these names are used in queries (e.g. `PowerSync.getAll("SELECT * FROM listsAlias");`). The `lists` and `todos` tables are not used in this state, but will become relevant in the next step.

When the user registers / signs in:

![diagram-2](./assets/local-only-readme-2.png)

The _synced_ tables (`lists` and `todos`) now have their view names overriden to `listsAlias` and `todosAlias`. Note that `updateSchema` must be run to update the view name. See the [schema](./lib/models/schema.dart) for details about this. The app query `PowerSync.getAll("SELECT * FROM listsAlias")` now reads data from the `lists` table. 

Finally, copy data from the local-only tables to the synced tables, and delete data from the local-only tables to reduce database size:

![diagram-3](./assets/local-only-readme-3.png)



At this point, being signed in no longer determines which schema should be used, as the user's session expiring and explicitly signing out trigger different behaviors. If the session expires, the user can continue interacting with their data. However, if the user explicitly logs out, all data is cleared, effectively resetting the app. To manage this, an additional local storage mechanism is used to track which schema is currently in use, as seen [here](./lib/models/sync_mode.dart). Note that any other local storage solution would work as long as it's not using the PowerSync database (chicken and egg problem).


# Limitations

- `updateSchema` cannot be called inside a transaction, and it's recommended to perform the schema update when the database isn't connected.
- Additionally, the current implementation of the PowerSync SDK's `watch` method may not correctly track tables that are altered by `updateSchema`. Note that `refreshSchema` can be executed after updating the schema to resolve this (the demo uses it in `switchToSyncedSchema` which can be viewed [here](./lib/models/schema.dart)).
