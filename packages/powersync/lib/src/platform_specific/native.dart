import 'dart:io';

import 'package:logging/logging.dart';
import 'package:sqlite_async/sqlite_async.dart';

import '../database/encryption_options.dart';
import '../database/native/native_powersync_database.dart';
import '../database/powersync_database.dart';
import '../open_factory/native/native_open_factory.dart';
import '../schema.dart';
import '../version.dart';
import 'int64.dart';

Int64 parseInt64(String s) => NativeInt64.parse(s);

Mutex potentiallySharedMutex(String identifier) {
  return Mutex.simple();
}

SqliteOpenFactory powerSyncOpenFactory(
  String path,
  SqliteOptions options,
  EncryptionOptions? encryption,
) {
  return NativePowerSyncOpenFactory(
    path: path,
    sqliteOptions: options,
    encryptionOptions: encryption,
  );
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

String powerSyncUserAgent() {
  var dartVersion = RegExp(r'[\w.]+').stringMatch(Platform.version);
  var dart = 'Dart';
  if (dartVersion != null) {
    dart = "Dart/$dartVersion";
  }
  // Ideally we'd get an OS version as well, but that's a little complex.
  // Platform.operatingSystemVersion is very verbose.
  return 'powersync-dart-core/$libraryVersion $dart ${Platform.operatingSystem}';
}

Map<String, String> userAgentHeaders() {
  return {'User-Agent': powerSyncUserAgent()};
}
