import 'package:logging/logging.dart';
import 'package:sqlite_async/sqlite_async.dart';

import '../database/encryption_options.dart';
import '../database/powersync_database.dart';
import '../schema.dart';

Never _unsupportedPlatform() {
  throw UnsupportedError('Unsupported platform for PowerSync SDK');
}

/// Creates a [Mutex] that might be shared across isolates and tabs.
///
/// This currently uses navigator locks on the web, but no shared mutexes for
/// isolates.
Mutex potentiallySharedMutex(String identifier) {
  _unsupportedPlatform();
}

SqliteOpenFactory powerSyncOpenFactory(
    String path, SqliteOptions options, EncryptionOptions? encryption) {
  _unsupportedPlatform();
}

BasePowerSyncDatabase openPowerSyncDatabase(
  Schema schema,
  SqliteDatabase database,
  Logger logger,
) {
  _unsupportedPlatform();
}
