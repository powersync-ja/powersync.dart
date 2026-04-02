import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart';
import 'package:logging/logging.dart';
import 'package:powersync/powersync.dart';
import 'package:powersync/src/abort_controller.dart';
import 'package:powersync/src/database/powersync_database.dart';
import 'package:powersync/src/sync/bucket_storage.dart';
import 'package:powersync/src/sync/internal_connector.dart';
import 'package:powersync/src/sync/options.dart';
import 'package:powersync/src/sync/streaming_sync.dart';
import 'package:sqlite3/common.dart';
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
        throw 'Unexpected severe error on logger: ${record.error!}';
      }

      uncaughtError();
    }
  });
  return logger;
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
  Future<SqliteOpenFactory> testFactory({
    String? path,
    SqliteOptions options = const SqliteOptions(),
    EncryptionOptions? encryption,
  });

  /// Creates a SqliteDatabaseConnection
  Future<PowerSyncDatabase> setupPowerSync({
    String? path,
    Schema? schema,
    Logger? logger,
    EncryptionOptions? encryption,
    bool initialize = true,
  }) async {
    final db = PowerSyncDatabase.withFactory(
        await testFactory(path: path, encryption: encryption),
        schema: schema ?? defaultSchema,
        logger: logger ?? _makeTestLogger(name: _testName));
    if (initialize) {
      await db.initialize();
    }
    addTearDown(db.close);
    return db;
  }

  /// Deletes any DB data
  Future<void> cleanDb({required String path});

  Future<CommonDatabase> openRawInMemoryDatabase();

  Future<(CommonDatabase, TestDatabase)> openInMemoryDatabase({
    Schema? schema,
    Logger? logger,
  }) async {
    final raw = await openRawInMemoryDatabase();
    return (raw, wrapRaw(raw, customSchema: schema, logger: logger));
  }

  TestDatabase wrapRaw(
    CommonDatabase raw, {
    Logger? logger,
    Schema? customSchema,
  }) {
    return TestDatabase(
      database: SqliteDatabase.singleConnection(
          SqliteConnection.synchronousWrapper(raw)),
      logger: logger ?? Logger.detached('PowerSync.test'),
      schema: customSchema ?? schema,
    );
  }
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

/// A [PowerSyncDatabase] implemented by a single in-memory database connection
/// and a mock-HTTP sync client.
///
/// This ensures tests for sync cover the `ConnectionManager` and other methods
/// exposed by the mixin.
final class TestDatabase extends BasePowerSyncDatabase {
  Client? httpClient;

  TestDatabase({
    required super.database,
    required super.logger,
    required super.schema,
  });

  @override
  Future<void> connectInternal({
    required PowerSyncBackendConnector connector,
    required ResolvedSyncOptions options,
    required List<SubscribedStream> initiallyActiveStreams,
    required Stream<List<SubscribedStream>> activeStreams,
    required AbortController abort,
    required Zone asyncWorkZone,
  }) async {
    final impl = StreamingSyncImplementation(
      adapter: BucketStorage(this),
      schemaJson: jsonEncode(this.schema),
      client: httpClient!,
      options: options,
      connector: InternalConnector.wrap(connector, this),
      logger: logger,
      crudUpdateTriggerStream: database
          .onChange(['ps_crud'], throttle: const Duration(milliseconds: 10)),
      activeSubscriptions: initiallyActiveStreams,
    );
    impl.statusStream.listen(setStatus);

    asyncWorkZone.run(impl.streamingSync);
    final subscriptions = activeStreams.listen(impl.updateSubscriptions);

    abort.onAbort.then((_) async {
      subscriptions.cancel();
      await impl.abort();
      abort.completeAbort();
    }).ignore();
  }

  @override
  Future<T> readLock<T>(Future<T> Function(SqliteReadContext tx) callback,
      {String? debugContext, Duration? lockTimeout}) async {
    await isInitialized;
    return database.readLock(callback,
        debugContext: debugContext, lockTimeout: lockTimeout);
  }

  @override
  Future<T> writeLock<T>(Future<T> Function(SqliteWriteContext tx) callback,
      {String? debugContext, Duration? lockTimeout}) async {
    await isInitialized;
    return database.writeLock(callback,
        debugContext: debugContext, lockTimeout: lockTimeout);
  }
}

extension MockSync on PowerSyncDatabase {
  StreamingSyncImplementation connectWithMockService(
    Client client,
    PowerSyncBackendConnector connector, {
    Logger? logger,
    SyncOptions options = const SyncOptions(retryDelay: Duration(seconds: 5)),
    Schema? customSchema,
  }) {
    final impl = StreamingSyncImplementation(
      adapter: BucketStorage(this),
      schemaJson: jsonEncode(customSchema ?? schema),
      client: client,
      options: ResolvedSyncOptions(options),
      connector: InternalConnector.wrap(connector, this),
      logger: logger,
      crudUpdateTriggerStream: database
          .onChange(['ps_crud'], throttle: const Duration(milliseconds: 10)),
    );
    impl.statusStream.listen(setStatus);

    return impl;
  }
}
