import 'dart:async';

import 'package:async/async.dart';
import 'package:logging/logging.dart';
import 'package:meta/meta.dart';
import 'package:powersync_core/sqlite3_common.dart';
import 'package:powersync_core/sqlite_async.dart';
import 'package:powersync_core/src/abort_controller.dart';
import 'package:powersync_core/src/connector.dart';
import 'package:powersync_core/src/crud.dart';
import 'package:powersync_core/src/database/active_instances.dart';
import 'package:powersync_core/src/database/core_version.dart';
import 'package:powersync_core/src/powersync_update_notification.dart';
import 'package:powersync_core/src/schema.dart';
import 'package:powersync_core/src/schema_logic.dart';
import 'package:powersync_core/src/schema_logic.dart' as schema_logic;
import 'package:powersync_core/src/sync/options.dart';
import 'package:powersync_core/src/sync/sync_status.dart';

mixin PowerSyncDatabaseMixin implements SqliteConnection {
  /// Schema used for the local database.
  Schema get schema;

  @internal
  set schema(Schema schema);

  /// The underlying database.
  ///
  /// For the most part, behavior is the same whether querying on the underlying
  /// database, or on [PowerSyncDatabase]. The main difference is in update notifications:
  /// the underlying database reports updates to the underlying tables, while
  /// [PowerSyncDatabase] reports updates to the higher-level views.
  SqliteDatabase get database;

  /// The Logger used by this [PowerSyncDatabase].
  ///
  /// The default is [autoLogger], which logs to the console in debug builds.
  /// Use [debugLogger] to always log to the console.
  /// Use [attachedLogger] to propagate logs to [Logger.root] for custom logging.
  Logger get logger;

  @Deprecated("This field is unused, pass params to connect() instead")
  Map<String, dynamic>? clientParams;

  /// Current connection status.
  SyncStatus currentStatus =
      const SyncStatus(connected: false, lastSyncedAt: null);

  /// Use this stream to subscribe to connection status updates.
  late final Stream<SyncStatus> statusStream;

  @protected
  StreamController<SyncStatus> statusStreamController =
      StreamController<SyncStatus>.broadcast();

  late final ActiveDatabaseGroup _activeGroup;

  /// An [ActiveDatabaseGroup] sharing mutexes for the sync client.
  ///
  /// This is used to ensure that, even if two databases to the same file are
  /// open concurrently, they won't both open a sync stream. Doing so would
  /// waste resources.
  @internal
  ActiveDatabaseGroup get group => _activeGroup;

  @override

  /// Broadcast stream that is notified of any table updates.
  ///
  /// Unlike in [SqliteDatabase.updates], the tables reported here are the
  /// higher-level views as defined in the [Schema], and exclude the low-level
  /// PowerSync tables.
  late final Stream<UpdateNotification> updates;

  /// Delay between retrying failed requests.
  /// Defaults to 5 seconds.
  /// Only has an effect if changed before calling [connect].
  @Deprecated('Set option when calling connect() instead')
  Duration retryDelay = const Duration(seconds: 5);

  @protected
  Future<void> get isInitialized;

  /// The abort controller for the current sync iteration.
  ///
  /// null when disconnected, present when connecting or connected.
  ///
  /// The controller must only be accessed from within a critical section of the
  /// sync mutex.
  @protected
  AbortController? _abortActiveSync;

  @protected
  Future<void> baseInit() async {
    String identifier = 'memory';
    try {
      identifier = database.openFactory.path;
    } catch (ignore) {
      // The in-memory database used in some tests doesn't have an open factory.
    }

    _activeGroup = ActiveDatabaseGroup.referenceDatabase(identifier);
    if (_activeGroup.refCount > 1) {
      logger.warning(
        'Multiple instances for the same database have been detected. '
        'This can cause unexpected results, please check your PowerSync client '
        'instantiation logic if this is not intentional',
      );
    }

    statusStream = statusStreamController.stream;
    updates = powerSyncUpdateNotifications(database.updates);

    await database.initialize();
    await _checkVersion();
    await database.execute('SELECT powersync_init()');
    await updateSchema(schema);
    await _updateHasSynced();
  }

  /// Check that a supported version of the powersync extension is loaded.
  Future<void> _checkVersion() async {
    // Get version
    String version;
    try {
      final row =
          await database.get('SELECT powersync_rs_version() as version');
      version = row['version'] as String;
    } catch (e) {
      throw SqliteException(
          1, 'The powersync extension is not loaded correctly. Details: $e');
    }

    PowerSyncCoreVersion.parse(version).checkSupported();
  }

  /// Wait for initialization to complete.
  ///
  /// While initializing is automatic, this helps to catch and report initialization errors.
  Future<void> initialize() {
    return isInitialized;
  }

  Future<void> _updateHasSynced() async {
    // Query the database to see if any data has been synced.
    final result = await database.getAll(
      'SELECT priority, last_synced_at FROM ps_sync_state ORDER BY priority;',
    );
    const prioritySentinel = 2147483647;
    var hasSynced = false;
    DateTime? lastCompleteSync;
    final priorityStatusEntries = <SyncPriorityStatus>[];

    DateTime parseDateTime(String sql) {
      return DateTime.parse('${sql}Z').toLocal();
    }

    for (final row in result) {
      final priority = row.columnAt(0) as int;
      final lastSyncedAt = parseDateTime(row.columnAt(1) as String);

      if (priority == prioritySentinel) {
        hasSynced = true;
        lastCompleteSync = lastSyncedAt;
      } else {
        priorityStatusEntries.add((
          hasSynced: true,
          lastSyncedAt: lastSyncedAt,
          priority: BucketPriority(priority)
        ));
      }
    }

    if (hasSynced != currentStatus.hasSynced) {
      final status = SyncStatus(
        hasSynced: hasSynced,
        lastSyncedAt: lastCompleteSync,
        priorityStatusEntries: priorityStatusEntries,
      );
      setStatus(status);
    }
  }

  /// Returns a [Future] which will resolve once at least one full sync cycle
  /// has completed (meaninng that the first consistent checkpoint has been
  /// reached across all buckets).
  ///
  /// When [priority] is null (the default), this method waits for the first
  /// full sync checkpoint to complete. When set to a [BucketPriority] however,
  /// it completes once all buckets within that priority (as well as those in
  /// higher priorities) have been synchronized at least once.
  Future<void> waitForFirstSync({BucketPriority? priority}) async {
    bool matches(SyncStatus status) {
      if (priority == null) {
        return status.hasSynced == true;
      } else {
        return status.statusForPriority(priority).hasSynced == true;
      }
    }

    if (matches(currentStatus)) {
      return;
    }
    await for (final result in statusStream) {
      if (matches(result)) {
        break;
      }
    }
  }

  @protected
  @visibleForTesting
  void setStatus(SyncStatus status) {
    if (status != currentStatus) {
      final newStatus = SyncStatus(
        connected: status.connected,
        downloading: status.downloading,
        uploading: status.uploading,
        connecting: status.connecting,
        uploadError: status.uploadError,
        downloadError: status.downloadError,
        priorityStatusEntries: status.priorityStatusEntries,
        downloadProgress: status.downloadProgress,
        // Note that currently the streaming sync implementation will never set
        // hasSynced. lastSyncedAt implies that syncing has completed at some
        // point (hasSynced = true).
        // The previous values of hasSynced should be preserved here.
        lastSyncedAt: status.lastSyncedAt ?? currentStatus.lastSyncedAt,
        hasSynced: status.lastSyncedAt != null
            ? true
            : status.hasSynced ?? currentStatus.hasSynced,
      );

      // If the absence of hasSynced was the only difference, the new states
      // would be equal and don't require an event. So, check again.
      if (newStatus != currentStatus) {
        currentStatus = newStatus;
        statusStreamController.add(currentStatus);
      }
    }
  }

  @override
  bool get closed {
    return database.closed;
  }

  /// Close the database, releasing resources.
  ///
  /// Also [disconnect]s any active connection.
  ///
  /// Once close is called, this connection cannot be used again - a new one
  /// must be constructed.
  @override
  Future<void> close() async {
    // Don't close in the middle of the initialization process.
    await isInitialized;
    // Disconnect any active sync connection.
    await disconnect();

    if (!database.closed) {
      // Now we can close the database
      await database.close();

      // If there are paused subscriptionso n the status stream, don't delay
      // closing the database because of that.
      unawaited(statusStreamController.close());
      await _activeGroup.close();
    }
  }

  /// Connect to the PowerSync service, and keep the databases in sync.
  ///
  /// The connection is automatically re-opened if it fails for any reason.
  ///
  /// To set sync parameters used in your sync rules (if any), use
  /// [SyncOptions.params]. [SyncOptions] can also be used to tune the behavior
  /// of the sync client, see that class for more information.
  ///
  /// Status changes are reported on [statusStream].
  Future<void> connect({
    required PowerSyncBackendConnector connector,
    SyncOptions? options,
    @Deprecated('Use SyncOptions.crudThrottleTime instead')
    Duration? crudThrottleTime,
    Map<String, dynamic>? params,
  }) async {
    // The initialization process acquires a sync connect lock (through
    // updateSchema), so ensure the database is ready before we try to acquire
    // the lock for the connection.
    await initialize();

    final resolvedOptions = ResolvedSyncOptions.resolve(
      options,
      crudThrottleTime: crudThrottleTime,
      // ignore: deprecated_member_use_from_same_package
      retryDelay: retryDelay,
      params: params,
    );

    if (schema.rawTables.isNotEmpty &&
        resolvedOptions.source.syncImplementation !=
            SyncClientImplementation.rust) {
      throw UnsupportedError(
          'Raw tables are only supported by the Rust client.');
    }

    // ignore: deprecated_member_use_from_same_package
    clientParams = params;
    var thisConnectAborter = AbortController();
    final zone = Zone.current;

    late void Function() retryHandler;

    Future<void> connectWithSyncLock() async {
      // Ensure there has not been a subsequent connect() call installing a new
      // sync client.
      assert(identical(_abortActiveSync, thisConnectAborter));
      assert(!thisConnectAborter.aborted);

      await connectInternal(
        connector: connector,
        options: resolvedOptions,
        abort: thisConnectAborter,
        // Run follow-up async tasks in the parent zone, a new one is introduced
        // while we hold the lock (and async tasks won't hold the sync lock).
        asyncWorkZone: zone,
      );

      thisConnectAborter.onCompletion.whenComplete(retryHandler);
    }

    // If the sync encounters a failure without being aborted, retry
    retryHandler = Zone.current.bindCallback(() async {
      _activeGroup.syncConnectMutex.lock(() async {
        // Is this still supposed to be active? (abort is only called within
        // mutex)
        if (!thisConnectAborter.aborted) {
          // We only change _abortActiveSync after disconnecting, which resets
          // the abort controller.
          assert(identical(_abortActiveSync, thisConnectAborter));

          // We need a new abort controller for this attempt
          _abortActiveSync = thisConnectAborter = AbortController();

          logger.warning('Sync client failed, retrying...');
          await connectWithSyncLock();
        }
      });
    });

    await _activeGroup.syncConnectMutex.lock(() async {
      // Disconnect a previous sync client, if one is active.
      await _abortCurrentSync();
      assert(_abortActiveSync == null);

      // Install the abort controller for this particular connect call, allowing
      // it to be disconnected.
      _abortActiveSync = thisConnectAborter;
      await connectWithSyncLock();
    });
  }

  /// Internal method to establish a sync client connection.
  ///
  /// This method will always be wrapped in an exclusive mutex through the
  /// [connect] method and should not be called elsewhere.
  /// This method will only be called internally when no other sync client is
  /// active, so the method should not call [disconnect] itself.
  @protected
  @internal
  Future<void> connectInternal({
    required PowerSyncBackendConnector connector,
    required ResolvedSyncOptions options,
    required AbortController abort,
    required Zone asyncWorkZone,
  });

  /// Close the sync connection.
  ///
  /// Use [connect] to connect again.
  Future<void> disconnect() async {
    // Also wrap this in the sync mutex to ensure there's no race between us
    // connecting and disconnecting.
    await _activeGroup.syncConnectMutex.lock(_abortCurrentSync);

    setStatus(
        SyncStatus(connected: false, lastSyncedAt: currentStatus.lastSyncedAt));
  }

  Future<void> _abortCurrentSync() async {
    if (_abortActiveSync case final disconnector?) {
      /// Checking `disconnecter.aborted` prevents race conditions
      /// where multiple calls to `disconnect` can attempt to abort
      /// the controller more than once before it has finished aborting.
      if (disconnector.aborted == false) {
        await disconnector.abort();
        _abortActiveSync = null;
      } else {
        /// Wait for the abort to complete. Continue updating the sync status after completed
        await disconnector.onCompletion;
      }
    }
  }

  /// Disconnect and clear the database.
  ///
  /// Use this when logging out.
  ///
  /// The database can still be queried after this is called, but the tables
  /// would be empty.
  ///
  /// To preserve data in local-only tables, set [clearLocal] to false.
  Future<void> disconnectAndClear({bool clearLocal = true}) async {
    await disconnect();

    await writeTransaction((tx) async {
      await tx.execute('select powersync_clear(?)', [clearLocal ? 1 : 0]);
    });
    // The data has been deleted - reset these
    currentStatus = SyncStatus(lastSyncedAt: null, hasSynced: false);
    statusStreamController.add(currentStatus);
  }

  @Deprecated('Use [disconnectAndClear] instead.')
  Future<void> disconnectedAndClear() async {
    await disconnectAndClear();
  }

  /// Whether a connection to the PowerSync service is currently open.
  bool get connected {
    return currentStatus.connected;
  }

  /// Replace the schema with a new version.
  /// This is for advanced use cases - typically the schema should just be
  /// specified once in the constructor.
  ///
  /// Cannot be used while connected - this should only be called before [connect].
  Future<void> updateSchema(Schema schema) async {
    schema.validate();

    await _activeGroup.syncConnectMutex.lock(() async {
      if (_abortActiveSync != null) {
        throw AssertionError('Cannot update schema while connected');
      }

      this.schema = schema;
      await database.writeLock((tx) => schema_logic.updateSchema(tx, schema));
    });
  }

  /// A connection factory that can be passed to different isolates.
  ///
  /// Use this to access the database in background isolates.
  IsolateConnectionFactory<CommonDatabase> isolateConnectionFactory() {
    return database.isolateConnectionFactory();
  }

  /// Get an unique id for this client.
  /// This id is only reset when the database is deleted.
  Future<String> getClientId() async {
    final row = await get('SELECT powersync_client_id() as client_id');
    return row['client_id'] as String;
  }

  /// Get upload queue size estimate and count.
  Future<UploadQueueStats> getUploadQueueStats(
      {bool includeSize = false}) async {
    if (includeSize) {
      final row = await getOptional(
          'SELECT SUM(cast(data as blob) + 20) as size, count(*) as count FROM ps_crud');
      return UploadQueueStats(
          count: row?['count'] as int? ?? 0, size: row?['size'] as int? ?? 0);
    } else {
      final row = await getOptional('SELECT count(*) as count FROM ps_crud');
      return UploadQueueStats(count: row?['count'] as int? ?? 0);
    }
  }

  /// Get a batch of crud data to upload.
  ///
  /// Returns null if there is no data to upload.
  ///
  /// Use this from the [PowerSyncBackendConnector.uploadData]` callback.
  ///
  /// Once the data have been successfully uploaded, call [CrudBatch.complete] before
  /// requesting the next batch.
  ///
  /// Use [limit] to specify the maximum number of updates to return in a single
  /// batch.
  ///
  /// This method does include transaction ids in the result, but does not group
  /// data by transaction. One batch may contain data from multiple transactions,
  /// and a single transaction may be split over multiple batches.
  Future<CrudBatch?> getCrudBatch({int limit = 100}) async {
    final rows = await getAll(
        'SELECT id, tx_id, data FROM ps_crud ORDER BY id ASC LIMIT ?',
        [limit + 1]);
    List<CrudEntry> all = [for (var row in rows) CrudEntry.fromRow(row)];

    var haveMore = false;
    if (all.length > limit) {
      all.removeLast();
      haveMore = true;
    }
    if (all.isEmpty) {
      return null;
    }
    final last = all[all.length - 1];
    return CrudBatch(
      crud: all,
      haveMore: haveMore,
      complete: _crudCompletionCallback(last.clientId),
    );
  }

  /// Get the next recorded transaction to upload.
  ///
  /// Returns null if there is no data to upload.
  ///
  /// Use this from the [PowerSyncBackendConnector.uploadData]` callback.
  ///
  /// Once the data have been successfully uploaded, call [CrudTransaction.complete] before
  /// requesting the next transaction.
  ///
  /// Unlike [getCrudBatch], this only returns data from a single transaction at a time.
  /// All data for the transaction is loaded into memory.
  Future<CrudTransaction?> getNextCrudTransaction() {
    return getCrudTransactions().firstOrNull;
  }

  /// Returns a stream of completed transactions with local writes against the
  /// database.
  ///
  /// This is typically used from the [PowerSyncBackendConnector.uploadData]
  /// method. Each entry emitted by the stream is a full transaction containing
  /// all local writes made while that transaction was active.
  ///
  /// Unlike [getNextCrudTransaction], which awalys returns the oldest
  /// transaction that hasn't been [CrudTransaction.complete]d yet, this stream
  /// can be used to receive multiple transactions. Calling
  /// [CrudTransaction.complete] will mark that transaction and all prior
  /// transactions emitted by the stream as completed.
  ///
  /// This can be used to upload multiple transactions in a single batch, e.g.
  /// with:
  ///
  /// ```dart
  /// CrudTransaction? lastTransaction;
  /// final batch = <CrudEntry>[];
  ///
  /// await for (final transaction in powersync.nextCrudTransactions()) {
  ///   batch.addAll(transaction.crud);
  ///   lastTransaction = transaction;
  ///
  ///   if (batch.length > 100) {
  ///     break;
  ///   }
  /// }
  ///
  /// if (batch.isNotEmpty) {
  ///   await uploadBatch(batch);
  ///   lastTransaction!.complete();
  /// }
  /// ```
  ///
  /// If there is no local data to upload, the stream emits a single `onDone`
  /// event.
  Stream<CrudTransaction> getCrudTransactions() async* {
    var lastCrudItemId = -1;
    const sql = '''
WITH RECURSIVE crud_entries AS (
  SELECT id, tx_id, data FROM ps_crud WHERE id = (SELECT min(id) FROM ps_crud WHERE id > ?)
  UNION ALL
  SELECT ps_crud.id, ps_crud.tx_id, ps_crud.data FROM ps_crud
    INNER JOIN crud_entries ON crud_entries.id + 1 = rowid
  WHERE crud_entries.tx_id = ps_crud.tx_id
)
SELECT * FROM crud_entries;
''';

    while (true) {
      final nextTransaction = await getAll(sql, [lastCrudItemId]);
      if (nextTransaction.isEmpty) {
        break;
      }

      final items = [for (var row in nextTransaction) CrudEntry.fromRow(row)];
      final last = items.last;
      final txId = last.transactionId;

      yield CrudTransaction(
        crud: items,
        complete: _crudCompletionCallback(last.clientId),
        transactionId: txId,
      );
      lastCrudItemId = last.clientId;
    }
  }

  Future<void> Function({String? writeCheckpoint}) _crudCompletionCallback(
      int lastClientId) {
    return ({String? writeCheckpoint}) async {
      await writeTransaction((db) async {
        await db.execute('DELETE FROM ps_crud WHERE id <= ?', [lastClientId]);
        if (writeCheckpoint != null &&
            await db.getOptional('SELECT 1 FROM ps_crud LIMIT 1') == null) {
          await db.execute(
              'UPDATE ps_buckets SET target_op = CAST(? as INTEGER) WHERE name=\'\$local\'',
              [writeCheckpoint]);
        } else {
          await db.execute(
              'UPDATE ps_buckets SET target_op = $maxOpId WHERE name=\'\$local\'');
        }
      });
    };
  }

  /// Takes a read lock, without starting a transaction.
  ///
  /// In most cases, [readTransaction] should be used instead.
  @override
  Future<T> readLock<T>(Future<T> Function(SqliteReadContext tx) callback,
      {String? debugContext, Duration? lockTimeout});

  /// Takes a global lock, without starting a transaction.
  ///
  /// In most cases, [writeTransaction] should be used instead.
  @override
  Future<T> writeLock<T>(Future<T> Function(SqliteWriteContext tx) callback,
      {String? debugContext, Duration? lockTimeout});

  @override
  Stream<ResultSet> watch(String sql,
      {List<Object?> parameters = const [],
      Duration throttle = const Duration(milliseconds: 30),
      Iterable<String>? triggerOnTables}) {
    if (triggerOnTables == null || triggerOnTables.isEmpty) {
      return database.watch(sql, parameters: parameters, throttle: throttle);
    }
    List<String> powersyncTables = [];
    for (String tableName in triggerOnTables) {
      powersyncTables.add(tableName);
      powersyncTables.add(_prefixTableNames(tableName, 'ps_data__'));
      powersyncTables.add(_prefixTableNames(tableName, 'ps_data_local__'));
    }
    return database.watch(sql,
        parameters: parameters,
        throttle: throttle,
        triggerOnTables: powersyncTables);
  }

  @protected
  String _prefixTableNames(String tableName, String prefix) {
    String prefixedString = tableName.replaceRange(0, 0, prefix);
    return prefixedString;
  }

  @override
  Future<bool> getAutoCommit() {
    return database.getAutoCommit();
  }

  @override
  Future<void> refreshSchema() async {
    await database.refreshSchema();
  }
}

Stream<UpdateNotification> powerSyncUpdateNotifications(
    Stream<UpdateNotification> inner) {
  return inner
      .map((update) =>
          PowerSyncUpdateNotification.fromUpdateNotification(update))
      .where((update) => update.isNotEmpty)
      .cast<UpdateNotification>();
}
