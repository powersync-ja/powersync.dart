@internal
library;

import 'dart:async';

import 'package:meta/meta.dart';
import 'package:sqlite_async/sqlite_async.dart';
import 'package:sqlite3/common.dart';

import '../crud.dart';
import '../schema_logic.dart';

@internal
extension type BucketStorage(SqliteConnection _internalDb) {
  // Use only for read statements
  Future<ResultSet> select(
    String query, [
    List<Object?> parameters = const [],
  ]) async {
    return await _internalDb.getAll(query, parameters);
  }

  Future<String> getClientId() async {
    final rows = await select('SELECT powersync_client_id() as client_id');
    return rows.first['client_id'] as String;
  }

  Future<T> writeTransaction<T>(
    Future<T> Function(SqliteWriteContext) run, {
    required Future<void> onAbort,
  }) {
    return _internalDb.abortableWriteLock(abortTrigger: onAbort, (lock) {
      return lock.writeTransaction(run);
    });
  }

  Future<bool> updateTargetCheckpointRequest(
    Future<String> Function() checkpointCallback,
  ) async {
    final currentTarget = await _internalDb.readTransaction(
      (db) => db.targetCheckpointRequestId(),
    );

    if (currentTarget != maxOpId) {
      // Nothing to update
      return false;
    }

    final rs = await select(
      'SELECT seq FROM main.sqlite_sequence WHERE name = \'ps_crud\'',
    );
    if (rs.isEmpty) {
      // Nothing to update
      return false;
    }
    int seqBefore = rs.first['seq'] as int;
    var opId = await checkpointCallback();

    return await _internalDb.writeTransaction((tx) async {
      final anyData = await tx.execute('SELECT 1 FROM ps_crud LIMIT 1');
      if (anyData.isNotEmpty) {
        return false;
      }
      final rs = await tx.execute(
        'SELECT seq FROM main.sqlite_sequence WHERE name = \'ps_crud\'',
      );
      assert(rs.isNotEmpty);

      int seqAfter = rs.first['seq'] as int;
      if (seqAfter != seqBefore) {
        // New crud data may have been uploaded since we got the checkpoint. Abort.
        return false;
      }

      await tx.targetCheckpointRequestId(opId);
      return true;
    });
  }

  Future<CrudEntry?> nextCrudItem() async {
    var next = await _internalDb.getOptional(
      'SELECT * FROM ps_crud ORDER BY id ASC LIMIT 1',
    );
    return next == null ? null : CrudEntry.fromRow(next);
  }

  Future<bool> hasCrud() async {
    final anyData = await select('SELECT 1 FROM ps_crud LIMIT 1');
    return anyData.isNotEmpty;
  }

  /// For tests only. Others should use the version on PowerSyncDatabase.
  Future<CrudBatch?> getCrudBatch({int limit = 100}) async {
    if (!(await hasCrud())) {
      return null;
    }

    final rows = await select('SELECT * FROM ps_crud ORDER BY id ASC LIMIT ?', [
      limit,
    ]);
    List<CrudEntry> all = [];
    for (var row in rows) {
      all.add(CrudEntry.fromRow(row));
    }
    if (all.isEmpty) {
      return null;
    }
    final last = all[all.length - 1];
    return CrudBatch(
      crud: all,
      haveMore: true,
      complete: crudCompletionCallback(last.clientId),
    );
  }

  Future<void> Function({String? writeCheckpoint}) crudCompletionCallback(
    int lastClientId,
  ) {
    return ({String? writeCheckpoint}) async {
      await _internalDb.writeTransaction((db) async {
        await db.execute('DELETE FROM ps_crud WHERE id <= ?', [lastClientId]);
        if (writeCheckpoint != null &&
            await db.getOptional('SELECT 1 FROM ps_crud LIMIT 1') == null) {
          await db.targetCheckpointRequestId(writeCheckpoint);
        } else {
          await db.targetCheckpointRequestId(maxOpId);
        }
      });
    };
  }

  Future<String> control(String op, [Object? payload]) async {
    return await _internalDb.writeTransaction((tx) async {
      return (await tx._control(op, payload))!;
    });
  }
}

extension PowerSyncControl on SqliteReadContext {
  Future<String?> _control(String op, [Object? payload]) async {
    final row = await get('SELECT CAST(powersync_control(?, ?) AS TEXT)', [
      op,
      payload,
    ]);
    return row.columnAt(0) as String?;
  }

  Future<String?> _checkpointRequestId(String type, String? update) async {
    return await _control('${type}_checkpoint_request_id', update);
  }

  /// Reads the current target checkpoint request id, or updates it when an
  /// [update] is supplied.
  ///
  /// The target checkpoint request is a checkpoint the sync service needs to
  /// include in a `checkpoint_complete` message for new changes to be applied.
  /// This guards against uploaded changes that have not yet been synced to
  /// flicker if we apply an intermediate checkpoint.
  ///
  /// [maxOpId] can be used as a sentinel value in case there are pending
  /// changes that have been uploaded, but for which no checkpoint request has
  /// been created yet.
  Future<String?> targetCheckpointRequestId([String? update]) {
    return _checkpointRequestId('target', update);
  }

  /// Reconciles a local checkpoint counter with a response from the service.
  ///
  /// Seeding checkpoint requests servces has two purposes:
  ///
  ///  1. The service is allowed to forget our checkpoint counter, so we remind
  ///     it whenever we connect.
  ///  2. Checkpoint requests are scoped to user and device ids, but our local
  ///     counter is per-device. Seeding ensures we correctly generate
  ///     incrementing checkpoint ids after switching accounts.
  Future<void> seedCheckpointRequestId(String serviceResponse) {
    return _checkpointRequestId('seed', serviceResponse);
  }

  /// The highest checkpoint request id that has been requested on this device.
  Future<String?> currentCheckpointRequestId() {
    return _checkpointRequestId('current', null);
  }

  /// Increments [currentCheckpointRequestId], used after uploading local
  /// mutations to require a new checkpoint.
  Future<String> nextCheckpointRequestId() async {
    // next_checkpoint_request_id cannot return null, the core extension would
    // report an error instead.
    return (await _checkpointRequestId('next', null))!;
  }
}
