import 'dart:ffi';
import 'dart:io';

import 'package:logging/logging.dart';
import 'package:powersync/powersync.dart';
import 'package:sqlite3/open.dart' as sqlite_open;
import 'package:sqlite3/sqlite3.dart' as sqlite;
import 'package:test_api/src/backend/invoker.dart';

const schema = Schema([
  Table('assets', [
    Column.text('created_at'),
    Column.text('make'),
    Column.text('model'),
    Column.text('serial_number'),
    Column.integer('quantity'),
    Column.text('user_id'),
    Column.text('customer_id'),
    Column.text('description'),
  ]),
  Table('customers', [Column.text('name'), Column.text('email')])
]);

DynamicLibrary _openOnLinux() {
  return DynamicLibrary.open('libsqlite3.so.0');
}

final testSetup = SqliteConnectionSetup(() async {
  sqlite_open.open.overrideFor(sqlite_open.OperatingSystem.linux, _openOnLinux);
});

Future<PowerSyncDatabase> setupPowerSync({required String path}) async {
  final db =
      PowerSyncDatabase(schema: schema, path: path, sqliteSetup: testSetup);
  await db.initialize();
  return db;
}

Future<sqlite.Database> setupSqlite(
    {required PowerSyncDatabase powersync}) async {
  await powersync.initialize();

  final sqliteDb = await powersync.connectionFactory().openRawDatabase();

  return sqliteDb;
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

String dbPath() {
  final test = Invoker.current!.liveTest;
  var testName = test.test.name;
  var testShortName = testName.replaceAll(RegExp(r'\s'), '_').toLowerCase();
  var dbName = "test-db/$testShortName.db";
  Directory("test-db").createSync(recursive: false);
  return dbName;
}

setupLogger() {
  Logger.root.level = Level.ALL;
  Logger.root.onRecord.listen((event) {
    print(event);
  });
}
