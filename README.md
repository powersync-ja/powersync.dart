<p align="center">
  <a href="https://www.powersync.com" target="_blank"><img src="https://github.com/powersync-ja/.github/assets/7372448/d2538c43-c1a0-4c47-9a76-41462dba484f"/></a>
</p>

_[PowerSync](https://www.powersync.com) keeps a client-side SQLite database in sync with your backend database. Changes appear across users and devices in real-time, user interactions feel instant and your app continues to work even when offline. Supports Postgres, MongoDB, MySQL, and SQL Server. Client SDKs are available for a wide range of environments including web, mobile, desktop, headless and embedded._

# PowerSync SDK for Dart and Flutter

| package                                                                                                                        | build                                                                                                                                                                                          | pub                                                                                                                                    | likes                                                                                                                                            | pub points                                                                                                                                             |
|--------------------------------------------------------------------------------------------------------------------------------|------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|----------------------------------------------------------------------------------------------------------------------------------------|--------------------------------------------------------------------------------------------------------------------------------------------------|--------------------------------------------------------------------------------------------------------------------------------------------------------|
| [powersync](https://github.com/powersync-ja/powersync.dart/tree/main/packages/powersync)                                       | [![build](https://github.com/powersync-ja/powersync.dart/actions/workflows/check.yml/badge.svg?branch=main)](https://github.com/powersync-ja/powersync.dart/actions?query=workflow%3Apackages) | [![pub package](https://img.shields.io/pub/v/powersync.svg)](https://pub.dev/packages/powersync)                                       | [![likes](https://img.shields.io/pub/likes/powersync?logo=dart)](https://pub.dev/packages/powersync/score)                                       | [![pub points](https://img.shields.io/pub/points/powersync?logo=dart)](https://pub.dev/packages/powersync/score)                                       |
| [powersync_attachments_helper](https://github.com/powersync-ja/powersync.dart/tree/main/packages/powersync_attachments_helper) | [![build](https://github.com/powersync-ja/powersync.dart/actions/workflows/check.yml/badge.svg?branch=main)](https://github.com/powersync-ja/powersync.dart/actions?query=workflow%3Apackages) | [![pub package](https://img.shields.io/pub/v/powersync_attachments_helper.svg)](https://pub.dev/packages/powersync_attachments_helper) | [![likes](https://img.shields.io/pub/likes/powersync_attachments_helper?logo=dart)](https://pub.dev/packages/powersync_attachments_helper/score) | [![pub points](https://img.shields.io/pub/points/powersync_attachments_helper?logo=dart)](https://pub.dev/packages/powersync_attachments_helper/score) |

#### Usage

This monorepo uses [melos](https://melos.invertase.dev/) to handle command and package management.

For detailed usage, check out the [powersync](https://github.com/powersync-ja/powersync.dart/tree/main/packages/powersync) package.

Additional packages in this repository are:

- [attachments helper](https://github.com/powersync-ja/powersync.dart/tree/main/packages/powersync_attachments_helper) (deprecated, a newer version of this is available in the `powersync` package).

To configure the monorepo for development, run `dart pub get` and `melos prepare` after cloning.

