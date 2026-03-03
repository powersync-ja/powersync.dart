# PowerSync + Supabase Flutter Demo: Todo List App

Demo app demonstrating use of the PowerSync SDK for Flutter together with Supabase.

To run this demo, you need to have properly configured Supabase and PowerSync projects. Follow the instructions below to set these up. 

# Set up Supabase Project

Detailed instructions for integrating PowerSync with Supabase can be found in [the integration guide](https://docs.powersync.com/integration-guides/supabase). Below are the main steps required to get this demo running. Create a new Supabase project, and paste an run the contents of [database.sql](./database.sql) in the Supabase SQL editor.

It does the following:

1. Create `lists` and `todos` tables.
2. Create a publication called `powersync` for `lists` and `todos`.
3. Enable row level security, allowing users to only view and edit their own data.
4. Create a trigger to populate some sample data when an user registers.

# Set up PowerSync Instance

Create a new PowerSync instance, connecting to the database of the Supabase project.

Then deploy the following Sync Streams. These streams use `auto_subscribe: true` so the client syncs the user's lists and todos automatically on connect:

```yaml
config:
  edition: 3

streams:
  user_lists:
    priority: 1
    auto_subscribe: true
    query: SELECT * FROM lists WHERE owner_id = auth.user_id()

  user_todos:
    auto_subscribe: true
    query: SELECT todos.* FROM todos INNER JOIN lists ON todos.list_id = lists.id WHERE lists.owner_id = auth.user_id()
```

**Note**: This config showcases [prioritized sync](https://docs.powersync.com/sync/advanced/prioritized-sync),
by syncing a user's lists with a higher priority than the items within a list (todos). If
priorities are not important, you can use a single stream instead (the app will work without changes):

```yaml
config:
  edition: 3

streams:
  user_data:
    auto_subscribe: true
    queries:
      - SELECT * FROM lists WHERE owner_id = auth.user_id()
      - SELECT todos.* FROM todos INNER JOIN lists ON todos.list_id = lists.id WHERE lists.owner_id = auth.user_id()
```

# Configure the app

Insert the credentials of your new Supabase and PowerSync projects into `lib/app_config.dart`

# Run the app

Ensure you have [melos](https://melos.invertase.dev/~melos-latest/getting-started) installed.

1. `cd demos/supabase-todolist`
2. `melos prepare`
3. `cp lib/app_config_template.dart lib/app_config.dart`
4. Insert your Supabase and PowerSync project credentials into `lib/app_config.dart` (See instructions below)
5. `flutter run`

