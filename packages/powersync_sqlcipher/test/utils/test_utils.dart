import 'dart:async';
import 'dart:ffi';
import 'dart:io';

import 'package:powersync_core/sqlite3_common.dart';
import 'package:powersync_core/sqlite_async.dart';
import 'package:powersync_sqlcipher/powersync.dart';
import 'package:test_api/src/backend/invoker.dart';
import 'package:powersync_core/sqlite3_open.dart' as sqlite_open;

const schema = Schema([
  Table('users', [
    Column.text('first_name'),
    Column.text('last_name'),
    Column.integer('age'),
    Column.integer('networth'),
  ], indexes: [
    Index('agenetworth', [IndexedColumn('age'), IndexedColumn('networth')])
  ]),
]);

class TestOpenFactory extends PowerSyncSQLCipherOpenFactory {
  TestOpenFactory({required super.path, required super.key});

  @override
  CommonDatabase open(SqliteOpenOptions options) {
    sqlite_open.open.overrideFor(sqlite_open.OperatingSystem.linux, () {
      return DynamicLibrary.open('libsqlcipher.so.0');
    });
    sqlite_open.open.overrideFor(sqlite_open.OperatingSystem.macOS, () {
      return DynamicLibrary.open('libsqlcipher.0.dylib');
    });
    return super.open(options);
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
      case Abi.linuxArm64:
        return '$path/libpowersync.so';
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

class TestUtils {
  String dbPath() {
    Directory("test-db").createSync(recursive: false);
    final test = Invoker.current!.liveTest;
    var testName = test.test.name;
    var testShortName =
        testName.replaceAll(RegExp(r'[\s\./]'), '_').toLowerCase();
    var dbName = "test-db/$testShortName.db";
    return dbName;
  }

  Future<void> cleanDb({required String path}) async {
    try {
      await File(path).delete();
    } on PathNotFoundException {
      // Not an issue
    }
    try {
      await File("$path-shm").delete();
    } on PathNotFoundException {
      // Not an issue
    }
    try {
      await File("$path-wal").delete();
    } on PathNotFoundException {
      // Not an issue
    }
  }

  Future<TestOpenFactory> testFactory({
    required String path,
    required String key,
    SqliteOptions options = const SqliteOptions.defaults(),
  }) async {
    return TestOpenFactory(path: path, key: key);
  }
}
