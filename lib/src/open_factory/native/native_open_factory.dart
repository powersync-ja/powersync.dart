import 'dart:io';
import 'dart:isolate';
import 'dart:ffi';

import 'package:powersync/sqlite3.dart';
import 'package:sqlite_async/sqlite3.dart' as sqlite;
import 'package:sqlite_async/sqlite3_common.dart';
import '../open_factory_interface.dart' as open_factory;

class PowerSyncOpenFactory extends open_factory.PowerSyncOpenFactory {
  PowerSyncOpenFactory(
      {required super.path,
      super.sqliteOptions,
      @Deprecated('Override PowerSyncOpenFactory instead')
      // ignore: deprecated_member_use_from_same_package
      open_factory.SqliteConnectionSetup? sqliteSetup});

  void enableExtension() {
    var powersync_lib = DynamicLibrary.open('libpowersync.so');
    sqlite.sqlite3.ensureExtensionLoaded(
        SqliteExtension.inLibrary(powersync_lib, 'sqlite3_powersync_init'));
  }

  void setupFunctions(CommonDatabase db) {
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
