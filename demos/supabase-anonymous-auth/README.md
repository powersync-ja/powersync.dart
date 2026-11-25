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

Copy [lib/app_config_template.dart](./lib/app_config_template.dart) to `lib/app_config.dart` and set your Supabase project URL, publishable key, and PowerSync instance URL. If you already have a local configuration, add `AppConfig.powersyncUrl` using the PowerSync instance URL returned by the anonymous Edge Function as `powersync_url`.
