import 'package:http/http.dart';
import 'package:logging/logging.dart';
import 'package:powersync_core/powersync_core.dart';
import 'package:powersync_core/src/sync/bucket_storage.dart';
import 'package:powersync_core/src/sync/internal_connector.dart';
import 'package:powersync_core/src/sync/options.dart';
import 'package:powersync_core/src/sync/streaming_sync.dart';
import 'package:sqlite_async/sqlite3_common.dart';
import 'package:sqlite_async/sqlite_async.dart';
import 'package:test/test.dart';
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

final testWarningLogger = _makeTestLogger(level: Level.WARNING);

Logger _makeTestLogger({Level level = Level.ALL, String? name}) {
  final logger = Logger.detached(name ?? 'PowerSync Tests');
  logger.level = level;
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

abstract mixin class TestPowerSyncFactory implements PowerSyncOpenFactory {
  Future<CommonDatabase> openRawInMemoryDatabase();

  Future<(CommonDatabase, PowerSyncDatabase)> openInMemoryDatabase() async {
    final raw = await openRawInMemoryDatabase();
    return (raw, wrapRaw(raw));
  }

  PowerSyncDatabase wrapRaw(
    CommonDatabase raw, {
    Logger? logger,
  }) {
    return PowerSyncDatabase.withDatabase(
      schema: schema,
      database: SqliteDatabase.singleConnection(
          SqliteConnection.synchronousWrapper(raw)),
      loggers: logger,
    );
  }
}

abstract class AbstractTestUtils {
  String get _testName => Invoker.current!.liveTest.test.name;

  String dbPath() {
    var testShortName =
        _testName.replaceAll(RegExp(r'[\s\./]'), '_').toLowerCase();
    var dbName = "test-db/$testShortName.db";
    return dbName;
  }

  /// Generates a test open factory
  Future<TestPowerSyncFactory> testFactory(
      {String? path,
      String sqlitePath = '',
      SqliteOptions options = const SqliteOptions.defaults()});

  /// Creates a SqliteDatabaseConnection
  Future<PowerSyncDatabase> setupPowerSync({
    String? path,
    Schema? schema,
    Logger? logger,
    bool initialize = true,
  }) async {
    final db = PowerSyncDatabase.withFactory(await testFactory(path: path),
        schema: schema ?? defaultSchema,
        logger: logger ?? _makeTestLogger(name: _testName));
    if (initialize) {
      await db.initialize();
    }
    addTearDown(db.close);
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

class TestConnector extends PowerSyncBackendConnector {
  Future<PowerSyncCredentials> Function() fetchCredentialsCallback;
  Future<void> Function(PowerSyncDatabase)? uploadDataCallback;

  TestConnector(this.fetchCredentialsCallback,
      {Future<void> Function(PowerSyncDatabase)? uploadData})
      : uploadDataCallback = uploadData;

  @override
  Future<PowerSyncCredentials?> fetchCredentials() {
    return fetchCredentialsCallback();
  }

  @override
  Future<void> uploadData(PowerSyncDatabase database) async {
    await uploadDataCallback?.call(database);
  }
}

extension MockSync on PowerSyncDatabase {
  StreamingSyncImplementation connectWithMockService(
    Client client,
    PowerSyncBackendConnector connector, {
    SyncOptions options = const SyncOptions(retryDelay: Duration(seconds: 5)),
  }) {
    final impl = StreamingSyncImplementation(
      adapter: BucketStorage(this),
      schema: schema,
      client: client,
      options: ResolvedSyncOptions(options),
      connector: InternalConnector.wrap(connector, this),
      crudUpdateTriggerStream: database
          .onChange(['ps_crud'], throttle: const Duration(milliseconds: 10)),
    );
    impl.statusStream.listen(setStatus);

    return impl;
  }
}
