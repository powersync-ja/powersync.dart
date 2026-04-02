import 'dart:ffi';
import 'dart:io';
import 'dart:math';

import 'package:sqlite3/sqlite3.dart';
import 'package:sqlite_async/sqlite_async.dart';
import 'package:sqlite_async/native.dart';

import 'sqlite3_powersync_init.dart';

var _didInstallExtension = false;

/// A [NativeSqliteOpenFactory] that also loads the PowerSync SQLite core
/// extension on opened databases.
base class NativePowerSyncOpenFactory extends NativeSqliteOpenFactory {
  NativePowerSyncOpenFactory({required super.path, super.sqliteOptions});

  @override
  List<String> pragmaStatements(SqliteOpenOptions options) {
    return [
      ...super.pragmaStatements(options),
      'PRAGMA recursive_triggers = TRUE',
    ];
  }

  void enableExtension() {
    if (!_didInstallExtension) {
      final entrypoint = Native.addressOf<NativeFunction<ExtensionEntrypoint>>(
          sqlite3_powersync_init);

      sqlite3.ensureExtensionLoaded(SqliteExtension(entrypoint.cast()));

      _didInstallExtension = true;
    }
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
  @override
  Database openNativeConnection(SqliteOpenOptions options) {
    enableExtension();

    final stopwatch = Stopwatch()..start();
    var retryDelay = 2;
    while (stopwatch.elapsedMilliseconds < 500) {
      try {
        return super.openNativeConnection(options);
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

  Database openConnectionAttempt(SqliteOpenOptions options) {
    return super.openNativeConnection(options);
  }
}
