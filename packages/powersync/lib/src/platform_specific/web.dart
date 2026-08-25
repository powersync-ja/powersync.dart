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

const _has64BitInts = !identical(0, 0.0);

final _intConversionBuffer = JSArrayBuffer(8);
final _intConversionView = JSDataView(_intConversionBuffer);

Int64 parseInt64(String s) {
  if (Int64.has64BitIntegers) {
    return NativeInt64.parse(s);
  } else {
    return JsBigInt64.parse(s);
  }
}

Int64 int64FromBigInt(JSBigInt value) {
  if (_has64BitInts) {
    _intConversionView.setBigInt64(0, value);
    final high = _intConversionView.getUint32(0).toDartInt;
    final low = _intConversionView.getUint32(4).toDartInt;

    return NativeInt64((high << 32) | low);
  } else {
    return JsBigInt64(value);
  }
}

final class JsBigInt64 implements Int64 {
  final JSBigInt value;

  JsBigInt64(this.value) : assert(!Int64.has64BitIntegers);

  static JsBigInt64 parse(String s) {
    return JsBigInt64(_stringToBigInt(s.toJS));
  }

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

extension on JSDataView {
  @JS()
  external JSNumber getUint32(int byteOffset);

  @JS()
  external void setBigInt64(int byteoffset, JSBigInt value);
}
