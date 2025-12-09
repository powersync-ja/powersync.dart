import 'dart:ffi';
import 'dart:io';

import 'package:path/path.dart';
import 'package:powersync_core/powersync_core.dart';
import 'package:powersync_core/sqlite3.dart' as sqlite;
import 'package:powersync_core/sqlite3_common.dart';
import 'package:powersync_core/sqlite3_open.dart' as sqlite_open;
import 'package:powersync_core/sqlite_async.dart';

const schema = Schema([
  Table('customers', [Column.text('name'), Column.text('email')])
]);

late PowerSyncDatabase db;

// Setup connector to backend if you would like to sync data.
class BackendConnector extends PowerSyncBackendConnector {
  PowerSyncDatabase db;

  BackendConnector(this.db);
  @override
  // ignore: body_might_complete_normally_nullable
  Future<PowerSyncCredentials?> fetchCredentials() async {
    // implement fetchCredentials
  }
  @override
  Future<void> uploadData(PowerSyncDatabase database) async {
    // implement uploadData
  }
}

/// Custom factory to load the PowerSync extension.
/// This is required to load the extension from a custom location.
/// The extension is required to sync data with the backend.
/// On macOS and Linux, the default sqlite3 library is overridden to load the extension.
class PowerSyncDartOpenFactory extends PowerSyncOpenFactory {
  PowerSyncDartOpenFactory({required super.path, super.sqliteOptions});

  @override
  CommonDatabase open(SqliteOpenOptions options) {
    sqlite_open.open.overrideFor(sqlite_open.OperatingSystem.linux, () {
      return DynamicLibrary.open('libsqlite3.so.0');
    });
    sqlite_open.open.overrideFor(sqlite_open.OperatingSystem.macOS, () {
      return DynamicLibrary.open('libsqlite3.dylib');
    });
    return super.open(options);
  }

  @override
  void enableExtension() {
    var powersyncLib = DynamicLibrary.open(getLibraryForPlatform());
    sqlite.sqlite3.ensureExtensionLoaded(sqlite.SqliteExtension.inLibrary(
        powersyncLib, 'sqlite3_powersync_init'));
  }

  @override
  String getLibraryForPlatform({String? path = "."}) {
    switch (Abi.current()) {
      case Abi.androidArm:
      case Abi.androidArm64:
      case Abi.androidX64:
        return '$path/libpowersync.so';
      case Abi.macosArm64:
      case Abi.macosX64:
        return '$path/libpowersync.dylib';
      case Abi.linuxX64:
        return '$path/llibpowersync_x64.linux.so';
      case Abi.linuxArm64:
        return '$path/llibpowersync_aarch64.linux.so';
      case Abi.windowsX64:
        return '$path/powersync.dll';
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

Future<String> getDatabasePath() async {
  const dbFilename = 'powersync-demo.db';
  final dir = (Directory.current.uri).toFilePath();
  return join(dir, dbFilename);
}

Future<void> openDatabase() async {
  // Setup the database.
  final psFactory = PowerSyncDartOpenFactory(path: await getDatabasePath());
  db = PowerSyncDatabase.withFactory(psFactory, schema: schema);

  // Initialise the database.
  await db.initialize();

  // Run local statements.
  await db.execute(
      'INSERT INTO customers(id, name, email) VALUES(uuid(), ?, ?)',
      ['Fred', 'fred@example.org']);

  // Connect to backend
  db.connect(connector: BackendConnector(db));
}
