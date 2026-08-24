import 'dart:js_interop';

import 'package:logging/logging.dart';
import 'package:sqlite_async/sqlite_async.dart';
// ignore: implementation_imports
import 'package:sqlite_async/src/web/web_mutex.dart';

import '../database/encryption_options.dart';
import '../database/powersync_database.dart';
import '../database/web/web_powersync_database.dart';
import '../open_factory/web/web_open_factory.dart';
import '../schema.dart';
import 'int64.dart';

/// Creates a [Mutex] that might be shared across isolates and tabs.
///
/// This currently uses navigator locks on the web, but no shared mutexes for
/// isolates.
Mutex potentiallySharedMutex(String identifier) {
  return WebMutexImpl(identifier: identifier);
}

SqliteOpenFactory powerSyncOpenFactory(
  String path,
  SqliteOptions options,
  EncryptionOptions? encryption,
) {
  return WebPowerSyncOpenFactory(
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
  return WebPowerSyncDatabase(
    schema: schema,
    database: database,
    logger: logger,
  );
}

Int64 parseInt64(String s) {
  const has64BitInts = !identical(0, 0.0);
  if (has64BitInts) {
    return NativeInt64.parse(s);
  } else {
    return JsBigInt64(_stringToBigInt(s.toJS));
  }
}

final class JsBigInt64 implements Int64 {
  final JSBigInt value;

  JsBigInt64(this.value);

  @override
  bool operator >=(Int64 other) {
    return other is JsBigInt64 &&
        value.greaterThanOrEqualTo(other.value).toDart;
  }

  @override
  String toString() {
    return _bigIntToString(value).toDart;
  }

  @override
  int get hashCode => _bigIntToDouble(value).toDartInt;

  @override
  bool operator ==(Object other) {
    return other is JsBigInt64 && value.strictEquals(other.value).toDart;
  }
}

@JS('String')
external JSString _bigIntToString(JSBigInt value);

@JS('Number')
external JSNumber _bigIntToDouble(JSBigInt value);

@JS('BigInt')
external JSBigInt _stringToBigInt(JSString value);
