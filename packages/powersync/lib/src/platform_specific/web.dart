import 'package:logging/logging.dart';
import 'package:sqlite_async/sqlite_async.dart';
// ignore: implementation_imports
import 'package:sqlite_async/src/web/web_mutex.dart';

import '../database/encryption_options.dart';
import '../database/powersync_database.dart';
import '../database/web/web_powersync_database.dart';
import '../open_factory/web/web_open_factory.dart';
import '../schema.dart';

/// Creates a [Mutex] that might be shared across isolates and tabs.
///
/// This currently uses navigator locks on the web, but no shared mutexes for
/// isolates.
Mutex potentiallySharedMutex(String identifier) {
  return WebMutexImpl(identifier: identifier);
}

SqliteOpenFactory powerSyncOpenFactory(
    String path, SqliteOptions options, EncryptionOptions? encryption) {
  return WebPowerSyncOpenFactory(
      path: path, sqliteOptions: options, encryptionOptions: encryption);
}

BasePowerSyncDatabase openPowerSyncDatabase(
  Schema schema,
  SqliteDatabase database,
  Logger logger,
) {
  return WebPowerSyncDatabase(
    schema: schema,
    database: database,
    logger: logger,
  );
}
