# PowerSync + Django Flutter Demo: Todo List App

Demo app demonstrating use of the PowerSync SDK for Flutter together with the [demo Django backend](https://github.com/powersync-ja/powersync-django-backend-todolist-demo).

# Running the app

Ensure you have [melos](https://melos.invertase.dev/~melos-latest/getting-started) installed.

1. `cd demos/django-todolist`
2. `melos bootstrap`
3. `cp lib/app_config_template.dart lib/app_config.dart`
4. Insert your Django URL and PowerSync project credentials into `lib/app_config.dart` (See instructions below)
5. `flutter run`

A test user with the following credentials will be available:

```
username: testuser
password: testpassword
```

# Service Configuration

This demo can be used with cloud or local services.

## Local Services

The [Self Hosting Demo](https://github.com/powersync-ja/self-host-demo) repository contains a Docker Compose Django backend demo which can be used with this client.
See [instructions](https://github.com/powersync-ja/self-host-demo/blob/main/demos/django/README.md) for starting the backend locally.

The backend demo should perform all the required setup automatically.

### Android

Note that Android requires port forwarding of local services. These can be configured with ADB as below:

```bash
adb reverse tcp:8080 tcp:8080 && adb reverse tcp:6061 tcp:6061
```

## Cloud Services

### Set up Django project

Follow the instructions in the django backend project's README.

The instructions guide you through the following:

1. Creates `lists` and `todos` tables.
2. Creates a test user.
3. Create a logical replication publication called `powersync` for `lists` and `todos`.

### Set up PowerSync Instance

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

### Configure the app

Insert the credentials of your new Django backend and PowerSync projects into `lib/app_config.dart`
