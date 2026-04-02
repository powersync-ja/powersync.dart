import 'package:logging/logging.dart';
import 'package:sqlite_async/sqlite_async.dart';

import '../database/encryption_options.dart';
import '../database/native/native_powersync_database.dart';
import '../database/powersync_database.dart';
import '../open_factory/native/native_open_factory.dart';
import '../schema.dart';

Mutex potentiallySharedMutex(String identifier) {
  return Mutex.simple();
}

SqliteOpenFactory powerSyncOpenFactory(
    String path, SqliteOptions options, EncryptionOptions? encryption) {
  return NativePowerSyncOpenFactory(
      path: path, sqliteOptions: options, encryptionOptions: encryption);
}

BasePowerSyncDatabase openPowerSyncDatabase(
  Schema schema,
  SqliteDatabase database,
  Logger logger,
) {
  return NativePowerSyncDatabase(
    schema: schema,
    database: database,
    logger: logger,
  );
}
