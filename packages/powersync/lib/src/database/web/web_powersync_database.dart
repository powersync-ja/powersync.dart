import 'dart:async';
import 'dart:convert';
import 'package:meta/meta.dart';
import 'package:http/browser_client.dart';
import 'package:powersync/src/abort_controller.dart';
import 'package:powersync/src/sync/bucket_storage.dart';
import 'package:powersync/src/connector.dart';
import 'package:powersync/src/database/powersync_database.dart';
import 'package:powersync/src/sync/internal_connector.dart';
import 'package:powersync/src/sync/streaming_sync.dart';
import 'package:sqlite_async/sqlite_async.dart';

import '../../sync/options.dart';
import '../../web/sync_controller.dart';

/// A PowerSync managed database.
///
/// Web implementation for [PowerSyncDatabase]
///
/// Use one instance per database file.
///
/// Use [PowerSyncDatabase.connect] to connect to the PowerSync service,
/// to keep the local database in sync with the remote database.
///
/// All changes to local tables are automatically recorded, whether connected
/// or not. Once connected, the changes are uploaded.
final class WebPowerSyncDatabase extends BasePowerSyncDatabase {
  WebPowerSyncDatabase(
      {required super.schema, required super.database, required super.logger});

  @override
  @internal
  Future<void> connectInternal({
    required PowerSyncBackendConnector connector,
    required AbortController abort,
    required List<SubscribedStream> initiallyActiveStreams,
    required Stream<List<SubscribedStream>> activeStreams,
    required Zone asyncWorkZone,
    required ResolvedSyncOptions options,
  }) async {
    final storage = BucketStorage(database);
    StreamingSync sync;
    // Try using a shared worker for the synchronization implementation to avoid
    // duplicating work across tabs.
    try {
      final workerUri = Uri.parse(
          database.openFactory.sqliteOptions.webSqliteOptions.workerUri);
      // This only affects our tests, where webSqliteOptions.workerUri is a blob
      // loading the worker. Using this as a sync worker seems to cause the test
      // runner to hang, so we want to throw an assertion error and continue
      // with the non-worker path.
      assert(
        workerUri.scheme != 'blob',
        'Falling back to local sync client instead of using blob worker.',
      );

      sync = await SyncWorkerHandle.start(
        database: this,
        connector: connector,
        options: options.source,
        workerUri: workerUri,
        subscriptions: initiallyActiveStreams,
      );
    } catch (e) {
      logger.warning(
        'Could not use shared worker for synchronization, falling back to locks.',
        e,
      );
      final crudStream =
          database.onChange(['ps_crud'], throttle: options.crudThrottleTime);

      sync = StreamingSyncImplementation(
        adapter: storage,
        schemaJson: jsonEncode(schema),
        connector: InternalConnector.wrap(connector, this),
        crudUpdateTriggerStream: crudStream,
        options: options,
        client: BrowserClient(),
        activeSubscriptions: initiallyActiveStreams,
        // Only allows 1 sync implementation to run at a time per database
        // This should be global (across tabs) when using Navigator locks.
        identifier: database.openFactory.path,
      );
    }

    sync.statusStream.listen((event) {
      setStatus(event);
    });
    sync.streamingSync();

    final subscriptions = activeStreams.listen(sync.updateSubscriptions);

    abort.onAbort.then((_) async {
      subscriptions.cancel();
      await sync.abort();
      abort.completeAbort();
    }).ignore();
  }

  /// Takes a read lock, without starting a transaction.
  ///
  /// In most cases, [readTransaction] should be used instead.
  @override
  Future<T> readLock<T>(Future<T> Function(SqliteReadContext tx) callback,
      {String? debugContext, Duration? lockTimeout}) async {
    await isInitialized;
    return database.readLock(callback,
        debugContext: debugContext, lockTimeout: lockTimeout);
  }

  @override
  Future<T> readTransaction<T>(
      Future<T> Function(SqliteReadContext tx) callback,
      {Duration? lockTimeout,
      String? debugContext}) async {
    await isInitialized;
    return database.readTransaction(callback, lockTimeout: lockTimeout);
  }

  /// Takes a global lock, without starting a transaction.
  ///
  /// In most cases, [writeTransaction] should be used instead.
  @override
  Future<T> writeLock<T>(Future<T> Function(SqliteWriteContext tx) callback,
      {String? debugContext, Duration? lockTimeout}) async {
    await isInitialized;
    return database.writeLock(callback,
        debugContext: debugContext, lockTimeout: lockTimeout);
  }

  /// Uses the database writeTransaction instead of the locally
  /// scoped writeLock. This is to allow the Database transaction
  /// tracking to be correctly configured.
  @override
  Future<T> writeTransaction<T>(
      Future<T> Function(SqliteWriteContext tx) callback,
      {Duration? lockTimeout,
      String? debugContext}) async {
    await isInitialized;
    return database.writeTransaction(callback, lockTimeout: lockTimeout);
  }
}
