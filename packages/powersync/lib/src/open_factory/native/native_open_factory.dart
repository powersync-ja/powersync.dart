import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'package:sqlite_async/sqlite3.dart' as sqlite;
import 'package:sqlite_async/sqlite3_common.dart';
import 'package:sqlite_async/sqlite_async.dart';
import '../abstract_powersync_open_factory.dart' as open_factory;
import '../abstract_powersync_open_factory.dart';
import '../../uuid.dart';

class PowerSyncOpenFactory extends AbstractPowerSyncOpenFactory {
  @Deprecated('Override PowerSyncOpenFactory instead')
  final open_factory.SqliteConnectionSetup? _sqliteSetup;

  PowerSyncOpenFactory(
      {required super.path,
      super.sqliteOptions,
      @Deprecated('Override PowerSyncOpenFactory instead')
      open_factory.SqliteConnectionSetup? sqliteSetup})
      // ignore: deprecated_member_use_from_same_package
      : _sqliteSetup = sqliteSetup;

  @override
  void enableExtension() {}

  @override
  setupFunctions(CommonDatabase db) {
    super.setupFunctions(db);
    db.createFunction(
      functionName: 'uuid',
      argumentCount: const AllowedArgumentCount(0),
      function: (args) {
        return uuid.v4();
      },
    );
    db.createFunction(
      // Postgres compatibility
      functionName: 'gen_random_uuid',
      argumentCount: const AllowedArgumentCount(0),
      function: (args) => uuid.v4(),
    );
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
  FutureOr<CommonDatabase> open(SqliteOpenOptions options) async {
    // ignore: deprecated_member_use_from_same_package
    _sqliteSetup?.setup();
    var db = await super.open(options);
    db.execute('PRAGMA recursive_triggers = TRUE');
    return db;
  }
}
