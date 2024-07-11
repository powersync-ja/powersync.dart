import 'package:logging/logging.dart';
import 'package:powersync/powersync.dart';
import 'package:sqlite_async/sqlite3_common.dart';
import 'package:sqlite_async/sqlite_async.dart';
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

abstract class AbstractTestUtils {
  String dbPath() {
    final test = Invoker.current!.liveTest;
    var testName = test.test.name;
    var testShortName =
        testName.replaceAll(RegExp(r'[\s\./]'), '_').toLowerCase();
    var dbName = "test-db/$testShortName.db";
    return dbName;
  }

  /// Generates a test open factory
  Future<PowerSyncOpenFactory> testFactory(
      {String? path,
      String sqlitePath = '',
      SqliteOptions options = const SqliteOptions.defaults()}) async {
    return PowerSyncOpenFactory(path: path ?? dbPath(), sqliteOptions: options);
  }

  /// Creates a SqliteDatabaseConnection
  Future<PowerSyncDatabase> setupPowerSync(
      {String? path, Schema? schema}) async {
    final db = PowerSyncDatabase.withFactory(await testFactory(path: path),
        schema: schema ?? defaultSchema, logger: testLogger);
    await db.initialize();
    return db;
  }

  Future<CommonDatabase> setupSqlite(
      {required PowerSyncDatabase powersync}) async {
    await powersync.initialize();

    final sqliteDb =
        await powersync.isolateConnectionFactory().openRawDatabase();

    return sqliteDb;
  }

  /// Deletes any DB data
  Future<void> cleanDb({required String path});
}
