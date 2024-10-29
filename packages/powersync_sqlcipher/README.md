<p align="center">
  <a href="https://www.powersync.com" target="_blank"><img src="https://github.com/powersync-ja/.github/assets/7372448/d2538c43-c1a0-4c47-9a76-41462dba484f"/></a>
</p>

# PowerSync with SQLCipher SDK for Flutter

_[PowerSync](https://www.powersync.com) is a sync engine for building local-first apps with instantly-responsive UI/UX and simplified state transfer. Syncs between SQLite on the client-side and Postgres or MongoDB on the server-side (MySQL coming soon)._

This package (`powersync_sqlcipher`) is the PowerSync client SDK for Flutter with encryption enabled using SQLCipher. 

If you do not require encryption, we recommend using the [`powersync`](/packages/powersync/README.md) SDK.

### Installing PowerSync with SQLCipher encryption in your own project

Install the latest version of the package, for example:

```bash
flutter pub add powersync_sqlcipher
```

Version history can be found [here](https://pub.dev/packages/powersync_sqlcipher/versions).

### Usage

This SDK requires a slightly different setup to the `powersync` package in order to encrypt the local database:

```Dart
import 'package/powersync_sqlcipher/powersync.dart';

/// Global reference to the database
late final PowerSyncDatabase db;

final cipherFactory = PowerSyncSQLCipherOpenFactory(
      path: path, key: "sqlcipher-encryption-key"); // https://www.zetetic.net/sqlcipher/sqlcipher-api/#key

db = PowerSyncDatabase.withFactory(cipherFactory, schema: schema);
```

# Getting Started

Our [full SDK reference](https://docs.powersync.com/client-sdk-references/flutter) contains everything you need to know to get started implementing PowerSync in your project.

# Changelog

A changelog for this SDK is available [here](https://pub.dev/packages/powersync_sqlcipher/changelog).

# API Reference

The full API reference for this SDK can be found [here](https://pub.dev/documentation/powersync_sqlcipher/latest/powersync_sqlcipher/powersync_sqlcipher-library.html).

# Examples

For example projects built with PowerSync and Flutter, see our [Demo Apps / Example Projects](https://docs.powersync.com/resources/demo-apps-example-projects#flutter) gallery. Most of these projects can also be found in the [`demos/`](../demos/) directory.

# Found a bug or need help?

- Join our [Discord server](https://discord.gg/powersync) where you can browse topics from our community, ask questions, share feedback, or just say hello :)
- Please open a [GitHub issue](https://github.com/powersync-ja/powersync.dart/issues) when you come across a bug.
- Have feedback or an idea? [Submit an idea](https://roadmap.powersync.com/tabs/5-roadmap/submit-idea) via our public roadmap or [schedule a chat](https://calendly.com/powersync/powersync-chat) with someone from our product team.
