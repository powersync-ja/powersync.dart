# PowerSync + Node.js + Firebase Auth + Flutter Demo: Todo List App

Demo app demonstrating use of the PowerSync SDK for Flutter together with a custom Node.js backend and using Firebase for user auth on the client.

This demo can run alongside the [powersync-nodejs-firebase-backend-todolist-demo](https://github.com/powersync-ja/powersync-nodejs-firebase-backend-todolist-demo) for testing and demo purposes.

We suggest you first set up the `powersync-nodejs-firebase-backend-todolist-demo` before setting up the client as shown in this repo.

# Running the app

Ensure you have [melos](https://melos.invertase.dev/~melos-latest/getting-started) installed.

1. `cd demos/firebase-nodejs-todolist`
2. `melos prepare`
3. `cp lib/app_config_template.dart lib/app_config.dart`
4. Insert your Supabase and PowerSync project credentials into `lib/app_config.dart` (See instructions below)
5. `flutter run`

# Add your Firebase app
Follow the step found in [this page](https://firebase.google.com/docs/flutter/setup?platform=ios) from the Firebase docs to login to your Firebase account and to initialize the Firebase credentials.

# Set up Supabase project

Create a new Supabase project, and paste and run the contents of [database.sql](./database.sql) in the Supabase SQL editor.

It does the following:

1. Create `lists` and `todos` tables.
2. Create a publication called `powersync` for `lists` and `todos`.
3. Enable row level security (RLS), allowing users to only view and edit their own data.
4. Create a trigger to populate some sample data when a user registers.

We won't be using the Supabase Flutter SDK for this demo, but rather as a hosted PostgresSQL database that the app connects to.

# Set up PowerSync Instance

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
