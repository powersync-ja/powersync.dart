import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:ffi';

import 'package:powersync/sqlite3.dart';
import 'package:sqlite_async/sqlite3.dart' as sqlite;
import 'package:sqlite_async/sqlite_async.dart';

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

class PowerSyncOpenFactory extends DefaultSqliteOpenFactory {
  @Deprecated('Override PowerSyncOpenFactory instead')
  final SqliteConnectionSetup? _sqliteSetup;

  PowerSyncOpenFactory(
      {required super.path,
      super.sqliteOptions,
      @Deprecated('Override PowerSyncOpenFactory instead')
      // ignore: deprecated_member_use_from_same_package
      SqliteConnectionSetup? sqliteSetup})
      // ignore: deprecated_member_use_from_same_package
      : _sqliteSetup = sqliteSetup;

  @override
  sqlite.Database open(SqliteOpenOptions options) {
    // ignore: deprecated_member_use_from_same_package
    _sqliteSetup?.setup();

    enableExtension();

    final db = super.open(options);
    setupFunctions(db);
    return db;
  }

  void enableExtension() {
    var powersync_lib = DynamicLibrary.open('libpowersync.so');
    sqlite.sqlite3.ensureExtensionLoaded(
        SqliteExtension.inLibrary(powersync_lib, 'sqlite3_powersync_init'));
  }

  void setupFunctions(sqlite.Database db) {
    db.createFunction(
      functionName: 'powersync_sleep',
      argumentCount: const sqlite.AllowedArgumentCount(1),
      function: (args) {
        final millis = args[0] as int;
        sleep(Duration(milliseconds: millis));
        return millis;
      },
    );

    db.createFunction(
      functionName: 'powersync_connection_name',
      argumentCount: const sqlite.AllowedArgumentCount(0),
      function: (args) {
        return Isolate.current.debugName;
      },
    );
  }
}
