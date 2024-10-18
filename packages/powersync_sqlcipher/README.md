<p align="center">
  <a href="https://www.powersync.com" target="_blank"><img src="https://github.com/powersync-ja/.github/assets/7372448/d2538c43-c1a0-4c47-9a76-41462dba484f"/></a>
</p>

# PowerSync with SQLCipher SDK for Flutter

_[PowerSync](https://www.powersync.com) is a sync engine for building local-first apps with instantly-responsive UI/UX and simplified state transfer. Syncs between SQLite on the client-side and Postgres or MongoDB on the server-side (MySQL coming soon)._

This package (`powersync_sqlcipher`) is the PowerSync client SDK for Dart/Flutter with encryption enabled using SQLCipher.

# Installation

```bash
flutter pub add powersync_sqlcipher
```

# Getting Started

Our [full SDK reference](https://docs.powersync.com/client-sdk-references/flutter) contains everything you need to know to get started implementing PowerSync in your project.

This SDK requires a slightly different setup in order to encrypt the local database.

### Usage

```Dart
import 'package/powersync_sqlcipher/powersync.dart';

/// Global reference to the database
late final PowerSyncDatabase db;

final cipherFactory = PowerSyncSQLCipherOpenFactory(
      path: path, key: "sqlcipher-encryption-key");

db = PowerSyncDatabase.withFactory(cipherFactory, schema: schema);
```

### Installing PowerSync in your own project

Install the latest version of the package, for example:

```
flutter pub add powersync_sqlcipher: ^0.1.0
```

The latest version can be found [here](https://pub.dev/packages/powersync_sqlcipher/versions).

### Demo app

The easiest way to test out the powersync is to run the [Supabase Todo-List](./demos/supabase-todolist) demo app:

1. Checkout [this repo's](https://github.com/powersync-ja/powersync.dart/tree/master) `master` branch.

- Note: If you are an existing user updating to the latest code after a git pull, run `melos exec 'flutter pub upgrade'` in the repo's root and make sure it succeeds.

2. Run `melos prepare` in the repo's root
3. cd into the `demos/supabase-todolist` folder
4. If you haven’t yet: `cp lib/app_config_template.dart lib/app_config.dart` (optionally update this config with your own Supabase and PowerSync project details).
5. Run `flutter run -d chrome`

[comment]: # "The sections below need to be updated"

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
