<p align="center">
  <a href="https://www.powersync.com" target="_blank"><img src="https://github.com/powersync-ja/.github/assets/7372448/d2538c43-c1a0-4c47-9a76-41462dba484f"/></a>
</p>

# PowerSync SDK for Dart and Flutter

_[PowerSync](https://www.powersync.com) keeps a client-side SQLite database in sync with your backend database. Changes appear across users and devices in real-time, user interactions feel instant and your app continues to work even when offline. Supports Postgres, MongoDB, MySQL, and SQL Server. Client SDKs are available for a wide range of environments including web, mobile, desktop, headless and embedded._

This package (`powersync`) is the PowerSync client SDK for Flutter.

See a summary of features [here](https://docs.powersync.com/client-sdk-references/flutter).

# Installation

Install the [latest version](https://pub.dev/packages/powersync/versions) of the package, for example:

```bash
dart pub add powersync
```

# Getting Started

Our [full SDK reference](https://docs.powersync.com/client-sdk-references/flutter) contains everything you need to know to get started implementing PowerSync in your project. 

## **Web support - Beta**

Flutter Web support in version `^1.9.0` is currently in a beta release. It is functionally ready for production use, provided that you've tested your use cases. 

Please familiarize yourself with the limitations for Flutter Web documented [here](https://docs.powersync.com/client-sdk-references/flutter/flutter-web-support#limitations).

### Demo app

The easiest way to test Flutter Web support is to run the [Supabase Todo-List](https://github.com/powersync-ja/powersync.dart/tree/main/demos/supabase-todolist) demo app:

1. Clone [this repo](https://github.com/powersync-ja/powersync.dart/tree/main).

- Note: If you are an existing user updating to the latest code after a git pull, run `melos exec 'flutter pub upgrade'` in the repo's root directory and make sure it succeeds.

2. Run `melos prepare` in the repo's root
3. cd into the `demos/supabase-todolist` folder
4. If you haven’t yet: `cp lib/app_config_template.dart lib/app_config.dart` (optionally update this config with your own Supabase and PowerSync project details).
5. Run `flutter run -d chrome`

#### Additional config

Additional config is required for web projects. Please see our docs [here](https://docs.powersync.com/client-sdk-references/flutter/flutter-web-support#additional-config) for details.

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
