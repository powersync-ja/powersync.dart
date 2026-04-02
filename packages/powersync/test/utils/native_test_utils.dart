import 'dart:async';
import 'dart:io';
import 'package:powersync/native.dart';
import 'package:powersync/powersync.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:sqlite3/src/database.dart';
import 'package:sqlite_async/sqlite_async.dart';

import 'abstract_test_utils.dart';

const defaultSqlitePath = 'libsqlite3.so.0';

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
  Future<SqliteOpenFactory> testFactory({
    String? path,
    SqliteOptions options = const SqliteOptions(),
    EncryptionOptions? encryption,
  }) async {
    return NativePowerSyncOpenFactory(
      path: path ?? dbPath(),
      sqliteOptions: options,
      encryptionOptions: encryption,
    );
  }

  @override
  Future<CommonDatabase> openRawInMemoryDatabase() async {
    NativePowerSyncOpenFactory(path: 'ignored').enableExtension();

    return sqlite3.openInMemory();
  }
}
