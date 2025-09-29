import 'dart:async';
import 'dart:math';

import 'package:meta/meta.dart';
import 'package:powersync_core/sqlite_async.dart';
import 'package:powersync_core/src/open_factory/common_db_functions.dart';
import 'package:sqlite_async/sqlite3_common.dart';

const powerSyncDefaultSqliteOptions = SqliteOptions(
    webSqliteOptions: WebSqliteOptions(
        wasmUri: 'sqlite3.wasm', workerUri: 'powersync_db.worker.js'));

abstract class AbstractPowerSyncOpenFactory extends DefaultSqliteOpenFactory {
  AbstractPowerSyncOpenFactory(
      {required super.path,
      super.sqliteOptions = powerSyncDefaultSqliteOptions});

  void enableExtension();

  void setupFunctions(CommonDatabase db) {
    return setupCommonDBFunctions(db);
  }

  @override
  List<String> pragmaStatements(SqliteOpenOptions options) {
    final basePragmaStatements = super.pragmaStatements(options);
    basePragmaStatements.add('PRAGMA recursive_triggers = TRUE');
    return basePragmaStatements;
  }

  @override
  CommonDatabase open(SqliteOpenOptions options) {
    var db = _retriedOpen(options);
    for (final statement in pragmaStatements(options)) {
      db.select(statement);
    }
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
  CommonDatabase _retriedOpen(SqliteOpenOptions options) {
    final stopwatch = Stopwatch()..start();
    var retryDelay = 2;
    while (stopwatch.elapsedMilliseconds < 500) {
      try {
        return super.open(options);
      } catch (e) {
        if (e is SqliteException && e.resultCode == 5) {
          sleep(Duration(milliseconds: retryDelay));
          retryDelay = min(retryDelay * 2, 16);
          continue;
        }
        rethrow;
      }
    }
    throw AssertionError('Cannot reach this point');
  }

  /// Returns the library name for the current platform.
  /// [path] is optional and is used when the library is not in the default location.
  String getLibraryForPlatform({String? path});

  /// On native platforms, synchronously pauses the current isolate for the
  /// given [Duration].
  @visibleForOverriding
  void sleep(Duration duration) {}
}

/// Advanced: Define custom setup for each SQLite connection.
@Deprecated('Use SqliteOpenFactory instead.')
class SqliteConnectionSetup {
  final FutureOr<void> Function() _setup;

  /// The setup parameter is called every time a database connection is opened.
  /// This can be used to configure dynamic library loading if required.
  const SqliteConnectionSetup(FutureOr<void> Function() setup) : _setup = setup;

  Future<void> setup() async {
    await _setup();
  }
}
