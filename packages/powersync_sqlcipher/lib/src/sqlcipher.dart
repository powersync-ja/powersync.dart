import 'package:powersync_core/powersync_core.dart';
import 'package:powersync_core/sqlite3_common.dart';
import 'package:powersync_core/sqlite3_open.dart' as sqlite3_open;
import 'package:powersync_core/sqlite_async.dart';
import 'package:sqlcipher_flutter_libs/sqlcipher_flutter_libs.dart';

/// A factory for opening a database with SQLCipher encryption.
/// An encryption [key] is required to open the database.
class PowerSyncSQLCipherOpenFactory extends PowerSyncOpenFactory {
  PowerSyncSQLCipherOpenFactory(
      {required super.path, required this.key, super.sqliteOptions});

  final String key;

  @override
  List<String> pragmaStatements(SqliteOpenOptions options) {
    final basePragmaStatements = super.pragmaStatements(options);
    return [
      // Set the encryption key as the first statement
      "PRAGMA KEY = '$key'",
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
      throw AssertionError(
          "SQLCipher was not initialized correctly. 'PRAGMA cipher_version' returned no rows.");
    } else {
      //TODO: Remove before publishing
      print("RUNNING with cipher ${versionRows.rows.first}");
    }
    return db;
  }
}
