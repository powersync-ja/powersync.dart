# PowerSync + Supabase Anonymous Auth

Demo app demonstrating use of anonymous authentication using Supabase with the PowerSync SDK for Flutter.

# Setup

* Create an edge anonymous auth function using <https://github.com/powersync-ja/powersync-jwks-example>

# Running the app

Install the Flutter SDK, then:

```sh
cp lib/app_config_template.dart lib/app_config.dart
flutter pub get
flutter run
```

# Configure the app

Copy the contents of  [lib/app_config_template.dart](./lib/app_config_template.dart) into `lib/app_config.dart`, and alter the values to use the credentials of your new Supabase project.
