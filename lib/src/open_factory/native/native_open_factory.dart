import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'package:sqlite_async/sqlite3.dart' as sqlite;
import 'package:sqlite_async/sqlite3_common.dart';
import 'package:sqlite_async/sqlite_async.dart';
import '../open_factory_interface.dart' as open_factory;
import '../open_factory_interface.dart';
import '../../uuid.dart';

class PowerSyncOpenFactory
    extends AbstractPowerSyncOpenFactory<sqlite.Database> {
  @Deprecated('Override PowerSyncOpenFactory instead')
  final open_factory.SqliteConnectionSetup? _sqliteSetup;

  PowerSyncOpenFactory(
      {required super.path,
      super.sqliteOptions,
      @Deprecated('Override PowerSyncOpenFactory instead')
      // ignore: deprecated_member_use_from_same_package
      open_factory.SqliteConnectionSetup? sqliteSetup})
      : _sqliteSetup = sqliteSetup;

  void enableExtension() {}

  @override
  setupFunctions(CommonDatabase db) {
    super.setupFunctions(db);

    // Native supports the faster uuid implementation which is provided by this package
    db.createFunction(
      functionName: 'uuid',
      argumentCount: const sqlite.AllowedArgumentCount(0),
      function: (args) {
        final id = uuid.v4();
        print('Creating a uuid' + id);
        return id;
      },
    );
    db.createFunction(
      // Postgres compatibility
      functionName: 'gen_random_uuid',
      argumentCount: const sqlite.AllowedArgumentCount(0),
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
  FutureOr<sqlite.Database> open(SqliteOpenOptions options) async {
    // ignore: deprecated_member_use_from_same_package
    _sqliteSetup?.setup();

    var db = await super.open(options);

    db.execute('PRAGMA recursive_triggers = TRUE');
    setupFunctions(db);

    return db;
  }
}
