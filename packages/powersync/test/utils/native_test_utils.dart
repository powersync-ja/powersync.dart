import 'dart:async';
import 'dart:ffi';
import 'dart:io';
import 'package:powersync/powersync.dart';
import 'package:sqlite_async/sqlite3_common.dart';
import 'package:sqlite_async/sqlite_async.dart';
import 'package:sqlite3/open.dart' as sqlite_open;

import 'abstract_test_utils.dart';

const defaultSqlitePath = 'libsqlite3.so.0';

class TestOpenFactory extends PowerSyncOpenFactory {
  TestOpenFactory({required super.path});

  @override
  CommonDatabase open(SqliteOpenOptions options) {
    sqlite_open.open.overrideFor(sqlite_open.OperatingSystem.linux, () {
      return DynamicLibrary.open('libsqlite3.so.0');
    });
    return super.open(options);
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
