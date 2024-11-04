<p align="center">
  <a href="https://www.powersync.com" target="_blank"><img src="https://github.com/powersync-ja/.github/assets/7372448/d2538c43-c1a0-4c47-9a76-41462dba484f"/></a>
</p>

# PowerSync SDK for Dart/Flutter

*[PowerSync](https://www.powersync.com) is a sync engine for building local-first apps with instantly-responsive UI/UX and simplified state transfer. Syncs between SQLite on the client-side and Postgres, MongoDB or MySQL on the server-side.*

This package (`powersync`) is the PowerSync client SDK for Dart/Flutter.

See a summary of features [here](https://docs.powersync.com/client-sdk-references/flutter).

# Installation

```bash
flutter pub add powersync
```

# Getting Started

Our [full SDK reference](https://docs.powersync.com/client-sdk-references/flutter) contains everything you need to know to get started implementing PowerSync in your project.

## **Web support - Beta**

Web support in version 1.9.0 is currently in a beta release. This means it is safe to use in production, provided that you've tested your use cases.

### Demo app

The easiest way to test Flutter Web support is to run the [Supabase Todo-List](https://github.com/powersync-ja/powersync.dart/tree/main/demos/supabase-todolist) demo app:

1. Checkout [this repo's](https://github.com/powersync-ja/powersync.dart/tree/main) `main` branch.

- Note: If you are an existing user updating to the latest code after a git pull, run `melos exec 'flutter pub upgrade'` in the repo's root directory and make sure it succeeds.

2. Run `melos prepare` in the repo's root
3. cd into the `demos/supabase-todolist` folder
4. If you haven’t yet: `cp lib/app_config_template.dart lib/app_config.dart` (optionally update this config with your own Supabase and PowerSync project details).
5. Run `flutter run -d chrome`

### Installing PowerSync in your own project

Install the latest version of the package, for example:

```
flutter pub add powersync:'^1.9.0'
```

The latest version can be found [here](https://pub.dev/packages/powersync/versions).

### Additional config

Web support requires `sqlite3.wasm` and worker (`powersync_db.worker.js` and `powersync_sync.worker.js`) assets to be served from the web application. They can be downloaded to the `web` directory by running the following command in your application's root folder.

```dart
dart run powersync:setup_web
```

The same code is used for initializing native and web `PowerSyncDatabase` clients.

### Limitations

The API for Web is essentially the same as for native platforms, however, some features within `PowerSyncDatabase` clients are not available.

#### Imports

Flutter Web does not support importing directly from `sqlite3.dart` as it uses `dart:ffi`.

Change imports from

```Dart
import 'package/powersync/sqlite3.dart`
```

to

```Dart
import 'package/powersync/sqlite3_common.dart'
```

In code which needs to run on the Web platform. Isolated native specific code can still import from `sqlite3.dart`.

#### Database connections

Web DB connections do not support concurrency. A single DB connection is used. `readLock` and `writeLock` contexts do not
implement checks for preventing writable queries in read connections and vice-versa.

Direct access to the synchronous `CommonDatabase` (`sqlite.Database` equivalent for web) connection is not available. `computeWithDatabase` is not available on web.

# Changelog

A changelog for this SDK is available [here](https://releases.powersync.com/announcements/flutter-client-sdk).

# API Reference

The full API reference for this SDK can be found [here](https://pub.dev/documentation/powersync/latest/powersync/powersync-library.html).

# Examples

For example projects built with PowerSync and Flutter, see our [Demo Apps / Example Projects](https://docs.powersync.com/resources/demo-apps-example-projects#flutter) gallery. Most of these projects can also be found in the [`demos/`](../demos/) directory.

# Found a bug or need help?

- Join our [Discord server](https://discord.gg/powersync) where you can browse topics from our community, ask questions, share feedback, or just say hello :)
- Please open a [GitHub issue](https://github.com/powersync-ja/powersync.dart/issues) when you come across a bug.
- Have feedback or an idea? [Submit an idea](https://roadmap.powersync.com/tabs/5-roadmap/submit-idea) via our public roadmap or [schedule a chat](https://calendly.com/powersync/powersync-chat) with someone from our product team.
