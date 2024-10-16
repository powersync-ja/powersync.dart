import 'dart:ffi';

import 'package:powersync_core/powersync_core.dart';
import 'package:powersync_core/sqlite3_common.dart';
import 'package:powersync_core/sqlite3_open.dart' as sqlite3_open;
import 'package:powersync_core/sqlite_async.dart';
import 'package:powersync_core/sqlite3.dart' as sqlite;
import 'package:sqlcipher_flutter_libs/sqlcipher_flutter_libs.dart';
import 'package:universal_io/io.dart';

/// A factory for opening a database with SQLCipher encryption.
/// An encryption [key] is required
class PowerSyncSQLCipherOpenFactory extends AbstractPowerSyncOpenFactory {
  PowerSyncSQLCipherOpenFactory({
    required super.path,
    required this.key,
    super.sqliteOptions = powerSyncDefaultSqliteOptions,
  });

  final String key;

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
  List<String> pragmaStatements(SqliteOpenOptions options) {
    final basePragmaStatements = super.pragmaStatements(options);
    return [
      // Set the encryption key as the first statement
      "PRAGMA KEY = '$key'",
      // Include the default statements afterwards
      for (var statement in basePragmaStatements) statement
    ];
  }

  @override
  CommonDatabase open(SqliteOpenOptions options) {
    sqlite3_open.open
        .overrideFor(sqlite3_open.OperatingSystem.android, openCipherOnAndroid);

    try {
      enableExtension();
    } on PowersyncNotReadyException catch (e) {
      autoLogger.severe(e.message);
      rethrow;
    }

    var db = super.open(options);
    final versionRows = db.select('PRAGMA cipher_version');
    if (versionRows.isEmpty) {
      throw AssertionError(
          "SQLCipher was not initialized correctly. 'PRAGMA cipher_version' returned no rows.");
    } else {
      //TODO: Remove before publishing
      print("RUNNING with cipher ${versionRows.rows.first}");
    }
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
        return 'libpowersync_x64.so';
      case Abi.linuxArm64:
        return 'libpowersync_aarch64.so';
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
}
