import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:math';

import 'package:sqlite_async/sqlite3.dart' as sqlite;
import 'package:sqlite_async/sqlite_async.dart';

import 'uuid.dart';

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
  @Deprecated('Override PowerSyncOpenFactory instead.')
  final SqliteConnectionSetup? _sqliteSetup;

  PowerSyncOpenFactory(
      {required super.path,
      super.sqliteOptions,
      @Deprecated('Override PowerSyncOpenFactory instead.')
      // ignore: deprecated_member_use_from_same_package
      SqliteConnectionSetup? sqliteSetup})
      // ignore: deprecated_member_use_from_same_package
      : _sqliteSetup = sqliteSetup;

  @override
  sqlite.Database open(SqliteOpenOptions options) {
    // ignore: deprecated_member_use_from_same_package
    _sqliteSetup?.setup();
    final db = _retriedOpen(options);
    db.execute('PRAGMA recursive_triggers = TRUE');
    setupFunctions(db);
    return db;
  }

  /// When opening the powersync connection and the standard write connection
  /// at the same time, one could fail with this error:
  ///
  ///     SqliteException(5): while opening the database, automatic extension loading failed: , database is locked (code 5)
  ///
  /// It happens before we have a chance to set the busy timeout, so we just
  /// retry opening the database.
  ///
  /// Usually a delay of 1-2ms is sufficient for the next try to succeed, but
  /// we increase the retry delay up to 16ms per retry, and a maximum of 500ms
  /// in total.
  sqlite.Database _retriedOpen(SqliteOpenOptions options) {
    final stopwatch = Stopwatch()..start();
    var retryDelay = 2;
    while (stopwatch.elapsedMilliseconds < 500) {
      try {
        return super.open(options);
      } catch (e) {
        if (e is sqlite.SqliteException && e.resultCode == 5) {
          sleep(Duration(milliseconds: retryDelay));
          retryDelay = min(retryDelay * 2, 16);
          continue;
        }
        rethrow;
      }
    }
    throw AssertionError('Cannot reach this point');
  }

  void setupFunctions(sqlite.Database db) {
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
}
