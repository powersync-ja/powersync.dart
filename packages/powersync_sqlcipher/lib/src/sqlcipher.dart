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
