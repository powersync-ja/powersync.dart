# PowerSync + Supabase Edge Function Auth

Demo app demonstrating use of custom authentication via Supabase edge functions with the PowerSync SDK for Flutter.

# Setup

* Create an edge auth function using <https://github.com/powersync-ja/powersync-jwks-example>

# Running the app

Install the Flutter SDK, then:

```sh
cp lib/app_config_template.dart lib/app_config.dart
flutter pub get
flutter run
```

# Configure the app

Insert the credentials of your new Supabase and PowerSync projects into `lib/app_config.dart`
