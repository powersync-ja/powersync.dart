import 'dart:async';
import 'dart:convert';

import 'package:sqlite_async/sqlite3_common.dart' as sqlite;
import 'package:sqlite_async/definitions.dart';
import 'package:sqlite_async/sqlite3_common.dart';

abstract class AbstractPowerSyncOpenFactory<T extends sqlite.CommonDatabase>
    extends DefaultSqliteOpenFactory<T> {
  AbstractPowerSyncOpenFactory(
      {required super.path,
      super.sqliteOptions = const SqliteOptions.defaults()});

  void enableExtension();

  void setupFunctions(CommonDatabase db) {
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
