import 'dart:async';
import 'dart:ffi';
import 'dart:io';
import 'package:powersync_core/powersync_core.dart';
import 'package:powersync_core/sqlite3.dart';
import 'package:sqlite_async/sqlite3_common.dart';
import 'package:sqlite_async/sqlite_async.dart';
import 'package:sqlite3/open.dart' as sqlite_open;

import 'abstract_test_utils.dart';

const defaultSqlitePath = 'libsqlite3.so.0';

class TestOpenFactory extends PowerSyncOpenFactory with TestPowerSyncFactory {
  TestOpenFactory({required super.path});

  void applyOpenOverride() {
    sqlite_open.open.overrideFor(sqlite_open.OperatingSystem.linux, () {
      return DynamicLibrary.open('libsqlite3.so.0');
    });
    sqlite_open.open.overrideFor(sqlite_open.OperatingSystem.macOS, () {
      // Prefer using Homebrew's SQLite which allows loading extensions.
      const fromHomebrew = '/opt/homebrew/opt/sqlite/lib/libsqlite3.dylib';
      if (File(fromHomebrew).existsSync()) {
        return DynamicLibrary.open(fromHomebrew);
      }

      return DynamicLibrary.open('libsqlite3.dylib');
    });
  }

  @override
  CommonDatabase open(SqliteOpenOptions options) {
    applyOpenOverride();
    return super.open(options);
  }

  @override
  Future<CommonDatabase> openRawInMemoryDatabase() async {
    applyOpenOverride();

    try {
      enableExtension();
    } on PowersyncNotReadyException catch (e) {
      autoLogger.severe(e.message);
      rethrow;
    }

    final db = sqlite3.openInMemory();
    setupFunctions(db);
    return db;
  }
}

class TestUtils extends AbstractTestUtils {
  @override
  String dbPath() {
    Directory("test-db").createSync(recursive: false);
    return super.dbPath();
  }

  @override
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

  @override
  Future<TestOpenFactory> testFactory(
      {String? path,
      String sqlitePath = defaultSqlitePath,
      SqliteOptions options = const SqliteOptions.defaults()}) async {
    return TestOpenFactory(path: path ?? dbPath());
  }
}
