import 'package:powersync/sqlite3_common.dart';
import 'package:sqlcipher_flutter_libs/sqlcipher_flutter_libs.dart';
import 'package:sqlite_async/sqlite_async.dart';
import 'package:universal_io/io.dart';
import 'package:sqlite_async/sqlite3_open.dart' as sqlite3_open;

import 'native_open_factory.dart';

class PowerSyncSqlcipherOpenFactory extends PowerSyncOpenFactory {
  String? key;
  PowerSyncSqlcipherOpenFactory({
    required super.path,
    required this.key,
    super.sqliteOptions,
  });

  @override
  CommonDatabase open(SqliteOpenOptions options) {
    if (Platform.isAndroid) {
      sqlite3_open.open.overrideFor(
          sqlite3_open.OperatingSystem.android, openCipherOnAndroid);
    }
    final db = super.open(options);
    if (key != null) {
      // Make sure that SQLCipher is used, not plain SQLite.
      final versionRows = db.select('PRAGMA cipher_version');
      if (versionRows.isEmpty) {
        throw AssertionError(
            'SQLite library is plain SQLite; SQLCipher expected.');
      } else {
        print("RUNNING with cipher ${versionRows.rows.first ?? 'failed'}");
        db.execute("PRAGMA key = '$key';");
      }
    }
    setupFunctions(db);
    return db;
  }
}
