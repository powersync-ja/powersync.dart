import 'dart:ffi';
import 'dart:io' as io;
import 'dart:io';
import 'dart:isolate';

import 'package:powersync_core/src/exceptions.dart';
import 'package:powersync_core/src/log.dart';
import 'package:powersync_core/src/open_factory/abstract_powersync_open_factory.dart';
import 'package:sqlite_async/sqlite3.dart' as sqlite;
import 'package:sqlite_async/sqlite3_common.dart';
import 'package:sqlite_async/sqlite_async.dart';

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
    var powersyncLib = _getDynamicLibraryForPlatform();
    sqlite.sqlite3.ensureExtensionLoaded(sqlite.SqliteExtension.inLibrary(
        powersyncLib, 'sqlite3_powersync_init'));
  }

  /// Returns the dynamic library for the current platform.
  DynamicLibrary _getDynamicLibraryForPlatform() {
    /// When running tests, we need to load the library for all platforms.
    if (Platform.environment.containsKey('FLUTTER_TEST')) {
      return DynamicLibrary.open(getLibraryForPlatform());
    }
    return (Platform.isIOS || Platform.isMacOS)
        ? DynamicLibrary.process()
        : DynamicLibrary.open(getLibraryForPlatform());
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
        return 'libpowersync_x64.linux.so';
      case Abi.linuxArm64:
        return 'libpowersync_aarch64.linux.so';
      case Abi.windowsX64:
        return 'powersync_x64.dll';
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

  @override
  void sleep(Duration duration) {
    io.sleep(duration);
  }
}
