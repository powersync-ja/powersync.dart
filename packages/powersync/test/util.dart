import 'dart:async';
import 'dart:ffi';
import 'dart:io';

import 'package:logging/logging.dart';
import 'package:powersync/powersync.dart';
import 'package:powersync/sqlite3.dart' as sqlite;
import 'package:powersync/sqlite_async.dart';
import 'package:sqlite3/open.dart' as sqlite_open;
import 'package:sqlite_async/sqlite3_common.dart';
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
  ], indexes: [
    Index('makemodel', [IndexedColumn('make'), IndexedColumn('model')])
  ]),
  Table('customers', [Column.text('name'), Column.text('email')])
]);

const defaultSchema = schema;

class TestOpenFactory extends PowerSyncOpenFactory {
  TestOpenFactory({required super.path});

  @override
  Future<CommonDatabase> open(SqliteOpenOptions options) async {
    sqlite_open.open.overrideFor(sqlite_open.OperatingSystem.linux, () {
      return DynamicLibrary.open('libsqlite3.so.0');
    });
    sqlite_open.open.overrideFor(sqlite_open.OperatingSystem.macOS, () {
      return DynamicLibrary.open('libsqlite3.dylib');
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
        return '$path/libpowersync.so';
      case Abi.windowsArm64:
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

Future<PowerSyncDatabase> setupPowerSync(
    {required String path, Schema? schema}) async {
  final db = PowerSyncDatabase.withFactory(TestOpenFactory(path: path),
      schema: schema ?? defaultSchema, logger: testLogger);
  return db;
}

Future<sqlite.Database> setupSqlite(
    {required PowerSyncDatabase powersync}) async {
  await powersync.initialize();

  final sqliteDb = await powersync.isolateConnectionFactory().openRawDatabase();

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

final testLogger = _makeTestLogger();

Logger _makeTestLogger() {
  final logger = Logger.detached('PowerSync Tests');
  logger.level = Level.ALL;
  logger.onRecord.listen((record) {
    print(
        '[${record.loggerName}] ${record.level.name}: ${record.time}: ${record.message}');
    if (record.error != null) {
      print(record.error);
    }
    if (record.stackTrace != null) {
      print(record.stackTrace);
    }

    if (record.error != null && record.level >= Level.SEVERE) {
      // Hack to fail the test if a SEVERE error is logged.
      // Not ideal, but works to catch "Sync Isolate error".
      uncaughtError() async {
        throw record.error!;
      }

      uncaughtError();
    }
  });
  return logger;
}
