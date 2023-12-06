import 'dart:async';

import 'package:sqlite_async/sqlite3_common.dart' as sqlite;
import 'package:sqlite_async/definitions.dart';

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

abstract class AbstractPowerSyncOpenFactory
    extends AbstractDefaultSqliteOpenFactory {
  const AbstractPowerSyncOpenFactory(
      {required super.path,
      super.sqliteOptions = const SqliteOptions.defaults()});

  void enableExtension();

  void setupFunctions(sqlite.CommonDatabase db);
}
