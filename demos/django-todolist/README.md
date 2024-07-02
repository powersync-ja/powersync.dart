# PowerSync + Django Flutter Demo: Todo List App

Demo app demonstrating use of the PowerSync SDK for Flutter together with the [demo Django backend](https://github.com/powersync-ja/powersync-django-backend-todolist-demo). 

# Running the app

Ensure you have [melos](https://melos.invertase.dev/~melos-latest/getting-started) installed.

1. `cd demos/django-todolist`
2. `melos bootstrap`
3. `cp lib/app_config_template.dart lib/app_config.dart`
4. Insert your Django URL and PowerSync project credentials into `lib/app_config.dart` (See instructions below)
5. `flutter run`

# Set up Django project

Follow the instructions in the django backend project's README. 

The instructions guide you through the following:

1. Creates `lists` and `todos` tables.
2. Creates a test user.
3. Create a logical replication publication called `powersync` for `lists` and `todos`.

# Set up PowerSync Instance

Create a new PowerSync instance by signing up for PowerSync Cloud at www.powersync.com, then connect to the database of your Django project.

Then deploy the following sync rules:

```yaml
bucket_definitions:
  user_lists:
    # Separate bucket per todo list
    parameters: select id as list_id from lists where owner_id = token_parameters.user_id
    data:
      - select * from lists where id = bucket.list_id
      - select * from todos where list_id = bucket.list_id
```

# Configure the app

Insert the credentials of your new Django backend and PowerSync projects into `lib/app_config.dart`
