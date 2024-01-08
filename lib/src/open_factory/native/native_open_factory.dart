import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'package:sqlite_async/sqlite3.dart' as sqlite;
import 'package:sqlite_async/sqlite_async.dart';
import 'package:sqlite_async/sqlite3_common.dart';
import '../../uuid.dart';
import '../open_factory_interface.dart' as open_factory;

class PowerSyncOpenFactory extends DefaultSqliteOpenFactory {
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

  void setupFunctions(CommonDatabase db) {
    db.createFunction(
      functionName: 'uuid',
      argumentCount: const sqlite.AllowedArgumentCount(0),
      function: (args) => uuid.v4(),
    );
    db.createFunction(
      // Postgres compatibility
      functionName: 'gen_random_uuid',
      argumentCount: const sqlite.AllowedArgumentCount(0),
      function: (args) => uuid.v4(),
    );

    db.createFunction(
        functionName: 'powersync_diff',
        argumentCount: const sqlite.AllowedArgumentCount(2),
        deterministic: true,
        directOnly: false,
        function: (args) {
          final oldData = jsonDecode(args[0] as String) as Map<String, dynamic>;
          final newData = jsonDecode(args[1] as String) as Map<String, dynamic>;

          Map<String, dynamic> result = {};

          for (final newEntry in newData.entries) {
            final oldValue = oldData[newEntry.key];
            final newValue = newEntry.value;

            if (newValue != oldValue) {
              result[newEntry.key] = newValue;
            }
          }

          for (final key in oldData.keys) {
            if (!newData.containsKey(key)) {
              result[key] = null;
            }
          }

          return jsonEncode(result);
        });

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
  sqlite.Database open(SqliteOpenOptions options) {
    // ignore: deprecated_member_use_from_same_package
    _sqliteSetup?.setup();

    final mode = options.openMode;
    print('opening db');
    print(path);
    print(mode);
    var db = super.open(options);

    db.execute('PRAGMA recursive_triggers = TRUE');
    setupFunctions(db);

    return db;
  }
}
