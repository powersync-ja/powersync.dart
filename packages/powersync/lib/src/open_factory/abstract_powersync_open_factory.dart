import 'dart:async';

import 'package:powersync/src/open_factory/common_db_functions.dart';
import 'package:sqlite_async/definitions.dart';
import 'package:sqlite_async/sqlite3_common.dart';

abstract class AbstractPowerSyncOpenFactory extends DefaultSqliteOpenFactory {
  AbstractPowerSyncOpenFactory(
      {required super.path,
      super.sqliteOptions = const SqliteOptions.defaults()});

  void enableExtension();

  void setupFunctions(CommonDatabase db) {
    return setupCommonDBFunctions(db);
  }

  @override
  FutureOr<CommonDatabase> open(SqliteOpenOptions options) async {
    var db = await super.open(options);
    setupFunctions(db);
    return db;
  }
}

/// Advanced: Define custom setup for each SQLite connection.
@Deprecated('Use SqliteOpenFactory instead')
class SqliteConnectionSetup {
  final FutureOr<void> Function() _setup;

  /// The setup parameter is called every time a database connection is opened.
  /// This can be used to configure dynamic library loading if required.
  const SqliteConnectionSetup(FutureOr<void> Function() setup) : _setup = setup;

  Future<void> setup() async {
    await _setup();
  }
}
