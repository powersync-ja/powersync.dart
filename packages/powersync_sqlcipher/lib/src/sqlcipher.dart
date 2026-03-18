import 'dart:ffi';
import 'dart:io';

import 'package:powersync_core/powersync_core.dart';
import 'package:powersync_core/sqlite3_common.dart';
import 'package:powersync_core/sqlite3_open.dart' as sqlite3_open;
import 'package:powersync_core/sqlite_async.dart';
import 'package:sqlcipher_flutter_libs/sqlcipher_flutter_libs.dart';

import 'shared.dart';

class _NativeCipherOpenFactory extends PowerSyncOpenFactory
    with BaseSQLCipherFactoryMixin {
  @override
  final String key;

  _NativeCipherOpenFactory({
    required super.path,
    required this.key,
    // ignore: unused_element_parameter
    super.sqliteOptions = defaultOptions,
  });

  @override
  CommonDatabase open(SqliteOpenOptions options) {
    sqlite3_open.open
        .overrideFor(sqlite3_open.OperatingSystem.android, openCipherOnAndroid);

    // iOS/macOS: explicitly load SQLCipher.framework by path instead of
    // relying on DynamicLibrary.process() (RTLD_DEFAULT), which resolves to
    // Apple's system sqlite3 first. Apple's sqlite3 has extension loading
    // disabled and returns SQLITE_MISUSE from sqlite3_auto_extension, causing
    // PowerSync's extension registration to fail.
    if (Platform.isIOS || Platform.isMacOS) {
      sqlite3_open.open.overrideForAll(
          () => DynamicLibrary.open('SQLCipher.framework/SQLCipher'));
    }

    var db = super.open(options);
    final versionRows = db.select('PRAGMA cipher_version');
    if (versionRows.isEmpty) {
      throw StateError(
          "SQLCipher was not initialized correctly. 'PRAGMA cipher_version' returned no rows.");
    }
    return db;
  }
}

typedef PowerSyncSQLCipherOpenFactory = _NativeCipherOpenFactory;
