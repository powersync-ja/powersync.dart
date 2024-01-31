import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:logging/logging.dart';
import 'package:powersync/src/database_utils.dart';
import 'package:powersync/src/migrations.dart';
import 'package:powersync/src/powersync_update_notification.dart';
import 'package:sqlite_async/sqlite3_common.dart';
import 'package:sqlite_async/sqlite_async.dart';

import '../abort_controller.dart';
import '../connector.dart';
import '../crud.dart';

import '../schema.dart';
import '../schema_helpers.dart';
import '../sync_status.dart';

/// A PowerSync managed database.
///
/// Use one instance per database file.
///
/// Use [PowerSyncDatabase.connect] to connect to the PowerSync service,
/// to keep the local database in sync with the remote database.
///
/// All changes to local tables are automatically recorded, whether connected
/// or not. Once connected, the changes are uploaded.
abstract class AbstractPowerSyncDatabase
    with SqliteQueries
    implements SqliteConnection {
  /// Schema used for the local database.
  Schema get schema;

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

  /// Current connection status.
  SyncStatus currentStatus =
      const SyncStatus(connected: false, lastSyncedAt: null);

  /// Use this stream to subscribe to connection status updates.
  late final Stream<SyncStatus> statusStream;

  @protected
  StreamController<SyncStatus> statusStreamController =
      StreamController<SyncStatus>.broadcast();

  /// Broadcast stream that is notified of any table updates.
  ///
  /// Unlike in [SqliteDatabase.updates], the tables reported here are the
  /// higher-level views as defined in the [Schema], and exclude the low-level
  /// PowerSync tables.
  late final Stream<UpdateNotification> updates;

  /// Delay between retrying failed requests.
  /// Defaults to 5 seconds.
  /// Only has an effect if changed before calling [connect].
  Duration retryDelay = const Duration(seconds: 5);

  @protected
  Future<void> get isInitialized;

  /// null when disconnected, present when connecting or connected
  @protected
  AbortController? disconnecter;

  @protected
  Future<void> baseInit() async {
    statusStream = statusStreamController.stream;
    updates = database.updates
        .map((update) =>
            PowerSyncUpdateNotification.fromUpdateNotification(update))
        .where((update) => update.isNotEmpty)
        .cast<UpdateNotification>();

    await database.initialize();
    await migrations.migrate(database);
    await updateSchema(schema);
  }

  /// Wait for initialization to complete.
  ///
  /// While initializing is automatic, this helps to catch and report initialization errors.
  Future<void> initialize() {
    return isInitialized;
  }

  void _setStatus(SyncStatus status) {
    if (status != currentStatus) {
      currentStatus = status;
      statusStreamController.add(status);
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
    // Now we can close the database
    await database.close();
  }

  /// Connect to the PowerSync service, and keep the databases in sync.
  ///
  /// The connection is automatically re-opened if it fails for any reason.
  ///
  /// Status changes are reported on [statusStream].
  connect({required PowerSyncBackendConnector connector});

  /// Close the sync connection.
  ///
  /// Use [connect] to connect again.
  Future<void> disconnect() async {
    if (disconnecter != null) {
      await disconnecter!.abort();
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
      await tx.execute('DELETE FROM ps_oplog');
      await tx.execute('DELETE FROM ps_crud');
      await tx.execute('DELETE FROM ps_buckets');

      final tableGlob = clearLocal ? 'ps_data_*' : 'ps_data__*';
      final existingTableRows = await tx.getAll(
          "SELECT name FROM sqlite_master WHERE type='table' AND name GLOB ?",
          [tableGlob]);

      for (var row in existingTableRows) {
        await tx.execute('DELETE FROM ${quoteIdentifier(row['name'])}');
      }
    });
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
  Future<void> updateSchema(Schema schema);

  /// A connection factory that can be passed to different isolates.
  ///
  /// Use this to access the database in background isolates.
  isolateConnectionFactory() {
    return database.isolateConnectionFactory();
  }

  /// Get upload queue size estimate and count.
  Future<UploadQueueStats> getUploadQueueStats(
      {bool includeSize = false}) async {
    if (includeSize) {
      final row = await getOptional(
          'SELECT SUM(cast(data as blob) + 20) as size, count(*) as count FROM ps_crud');
      return UploadQueueStats(
          count: row?['count'] ?? 0, size: row?['size'] ?? 0);
    } else {
      final row = await getOptional('SELECT count(*) as count FROM ps_crud');
      return UploadQueueStats(count: row?['count'] ?? 0);
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
  Future<CrudBatch?> getCrudBatch({limit = 100}) async {
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
        complete: ({String? writeCheckpoint}) async {
          await writeTransaction((db) async {
            await db
                .execute('DELETE FROM ps_crud WHERE id <= ?', [last.clientId]);
            if (writeCheckpoint != null &&
                await db.getOptional('SELECT 1 FROM ps_crud LIMIT 1') == null) {
              await db.execute(
                  'UPDATE ps_buckets SET target_op = $writeCheckpoint WHERE name=\'\$local\'');
            } else {
              await db.execute(
                  'UPDATE ps_buckets SET target_op = $maxOpId WHERE name=\'\$local\'');
            }
          });
        });
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
  Future<CrudTransaction?> getNextCrudTransaction() async {
    return await readTransaction((tx) async {
      final first = await tx.getOptional(
          'SELECT id, tx_id, data FROM ps_crud ORDER BY id ASC LIMIT 1');
      if (first == null) {
        return null;
      }
      final int? txId = first['tx_id'];
      List<CrudEntry> all;
      if (txId == null) {
        all = [CrudEntry.fromRow(first)];
      } else {
        final rows = await tx.getAll(
            'SELECT id, tx_id, data FROM ps_crud WHERE tx_id = ? ORDER BY id ASC',
            [txId]);
        all = [for (var row in rows) CrudEntry.fromRow(row)];
      }

      final last = all[all.length - 1];

      return CrudTransaction(
          transactionId: txId,
          crud: all,
          complete: ({String? writeCheckpoint}) async {
            await writeTransaction((db) async {
              await db.execute(
                  'DELETE FROM ps_crud WHERE id <= ?', [last.clientId]);
              if (writeCheckpoint != null &&
                  await db.getOptional('SELECT 1 FROM ps_crud LIMIT 1') ==
                      null) {
                await db.execute(
                    'UPDATE ps_buckets SET target_op = $writeCheckpoint WHERE name=\'\$local\'');
              } else {
                await db.execute(
                    'UPDATE ps_buckets SET target_op = $maxOpId WHERE name=\'\$local\'');
              }
            });
          });
    });
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
  Future<T> writeTransaction<T>(
      Future<T> Function(SqliteWriteContext tx) callback,
      {Duration? lockTimeout,
      String? debugContext}) async {
    return writeLock((ctx) async {
      return await internalTrackedWriteTransaction(ctx, callback);
    },
        lockTimeout: lockTimeout,
        debugContext: debugContext ?? 'writeTransaction()');
  }

  @override
  Future<ResultSet> execute(String sql,
      [List<Object?> parameters = const []]) async {
    return writeLock((ctx) async {
      try {
        await ctx.execute(
            'UPDATE ps_tx SET current_tx = next_tx, next_tx = next_tx + 1 WHERE id = 1');
        return await ctx.execute(sql, parameters);
      } finally {
        await ctx.execute('UPDATE ps_tx SET current_tx = NULL WHERE id = 1');
      }
    }, debugContext: 'execute()');
  }

  @override
  Future<bool> getAutoCommit() {
    return database.getAutoCommit();
  }
}
