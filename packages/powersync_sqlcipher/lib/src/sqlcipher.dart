import 'package:powersync_core/sqlite3_common.dart';
import 'package:powersync_core/sqlite3_open.dart' as sqlite3_open;
import 'package:powersync_core/sqlite_async.dart';
import 'package:sqlcipher_flutter_libs/sqlcipher_flutter_libs.dart';

import '../powersync.dart';

final class _NativeCipherOpenFactory extends PowerSyncOpenFactory
    implements PowerSyncSQLCipherOpenFactory {
  @override
  final String key;

  _NativeCipherOpenFactory({
    required super.path,
    required this.key,
    super.sqliteOptions,
  });

  @override
  List<String> pragmaStatements(SqliteOpenOptions options) {
    final basePragmaStatements = super.pragmaStatements(options);
    return [
      // Set the encryption key as the first statement
      "PRAGMA KEY = ${quoteString(key)}",
      // Include the default statements afterwards
      for (var statement in basePragmaStatements) statement
    ];
  }

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

PowerSyncSQLCipherOpenFactory cipherFactory({
  required String path,
  required String key,
  required SqliteOptions options,
}) {
  return _NativeCipherOpenFactory(path: path, key: key, sqliteOptions: options);
}
