import 'dart:ffi';
import 'dart:io' as io;
import 'dart:isolate';

import 'package:powersync_core/src/exceptions.dart';
import 'package:powersync_core/src/log.dart';
import 'package:powersync_core/src/open_factory/abstract_powersync_open_factory.dart';
import 'package:sqlite_async/sqlite3.dart' as sqlite;
import 'package:sqlite_async/sqlite3_common.dart';
import 'package:sqlite_async/sqlite_async.dart';

import 'sqlite3_powersync_init.dart';

/// Native implementation for [AbstractPowerSyncOpenFactory]
class PowerSyncOpenFactory extends AbstractPowerSyncOpenFactory {
  @Deprecated('Override PowerSyncOpenFactory instead.')
  final SqliteConnectionSetup? _sqliteSetup;

  PowerSyncOpenFactory({
    required super.path,
    super.sqliteOptions,
    @Deprecated('Override PowerSyncOpenFactory instead.')
    SqliteConnectionSetup? sqliteSetup,
  })
  // ignore: deprecated_member_use_from_same_package
  : _sqliteSetup = sqliteSetup;

  @override
  void enableExtension() {
    final entrypoint = Native.addressOf<NativeFunction<ExtensionEntrypoint>>(
        sqlite3_powersync_init);

    sqlite.sqlite3
        .ensureExtensionLoaded(sqlite.SqliteExtension(entrypoint.cast()));
  }

  @override
  setupFunctions(CommonDatabase db) {
    super.setupFunctions(db);
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

  @override
  CommonDatabase open(SqliteOpenOptions options) {
    // ignore: deprecated_member_use_from_same_package
    _sqliteSetup?.setup();

    try {
      enableExtension();
    } on PowersyncNotReadyException catch (e) {
      autoLogger.severe(e.message);
      rethrow;
    }

    var db = super.open(options);
    db.execute('PRAGMA recursive_triggers = TRUE');
    return db;
  }

  @override
  void sleep(Duration duration) {
    io.sleep(duration);
  }
}
