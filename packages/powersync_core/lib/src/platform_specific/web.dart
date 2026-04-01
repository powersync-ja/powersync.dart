import 'package:logging/logging.dart';
import 'package:sqlite_async/sqlite_async.dart';

import '../database/powersync_database.dart';
import '../database/web/web_powersync_database.dart';
import '../open_factory/web/web_open_factory.dart';
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

SqliteOpenFactory powerSyncOpenFactory(String path, SqliteOptions options) {
  return WebPowerSyncOpenFactory(path: path, sqliteOptions: options);
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
