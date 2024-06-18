import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:ffi';
import 'dart:math';

import 'package:powersync/sqlite3.dart';
import 'package:powersync/src/exceptions.dart';
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

    enableExtension();

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

  void enableExtension() {
    var powersyncLib = _getDynamicLibraryForPlatform();
    sqlite.sqlite3.ensureExtensionLoaded(
        SqliteExtension.inLibrary(powersyncLib, 'sqlite3_powersync_init'));
  }

  DynamicLibrary _getDynamicLibraryForPlatform() {
    if (Platform.environment.containsKey('FLUTTER_TEST')) {
      return DynamicLibrary.open(getLibraryForPlatform());
    }
    return (Platform.isIOS || Platform.isMacOS)
        ? DynamicLibrary.process()
        : DynamicLibrary.open(getLibraryForPlatform());
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

  /// Returns the library name for the current platform.
  /// [path] is optional and is used when the library is not in the default location.
  String getLibraryForPlatform({String? path}) {
    switch (Abi.current()) {
      case Abi.androidArm:
      case Abi.androidArm64:
      case Abi.androidX64:
        return 'libpowersync.so';
      case Abi.macosArm64:
      case Abi.macosX64:
        return 'libpowersync.dylib';
      case Abi.linuxX64:
        return 'libpowersync.so';
      case Abi.windowsArm64:
      case Abi.windowsX64:
        return 'powersync.dll';
      case Abi.androidIA32:
        throw PowersyncNotReadyException(
          'Unsupported processor architecture. X86 Android emulators are not '
          'supported. Please use an x86_64 emulator instead. All physical '
          'Android devices are supported including 32bit ARM.',
        );
      default:
        throw PowersyncNotReadyException(
          'Unsupported processor architecture "${Abi.current()}". '
          'Please open an issue on GitHub to request it.',
        );
    }
  }
}
