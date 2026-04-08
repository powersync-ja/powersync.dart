@internal
library;

import 'dart:async';

import 'package:meta/meta.dart';
import 'package:sqlite_async/sqlite_async.dart';
import 'package:sqlite3/common.dart';

import '../crud.dart';
import '../schema_logic.dart';

class BucketStorage {
  final SqliteConnection _internalDb;

  BucketStorage(this._internalDb);

  // Use only for read statements
  Future<ResultSet> select(String query,
      [List<Object?> parameters = const []]) async {
    return await _internalDb.execute(query, parameters);
  }

  Future<String> getClientId() async {
    final rows = await select('SELECT powersync_client_id() as client_id');
    return rows.first['client_id'] as String;
  }

  Future<bool> updateLocalTarget(
      Future<String> Function() checkpointCallback) async {
    final rs1 = await select(
        'SELECT CAST(target_op AS TEXT) FROM ps_buckets WHERE name = \'\$local\' AND target_op = $maxOpId');
    if (rs1.isEmpty) {
      // Nothing to update
      return false;
    }
    final rs = await select(
        'SELECT seq FROM main.sqlite_sequence WHERE name = \'ps_crud\'');
    if (rs.isEmpty) {
      // Nothing to update
      return false;
    }
    int seqBefore = rs.first['seq'] as int;
    var opId = await checkpointCallback();

    return await writeTransaction((tx) async {
      final anyData = await tx.execute('SELECT 1 FROM ps_crud LIMIT 1');
      if (anyData.isNotEmpty) {
        return false;
      }
      final rs = await tx.execute(
          'SELECT seq FROM main.sqlite_sequence WHERE name = \'ps_crud\'');
      assert(rs.isNotEmpty);

      int seqAfter = rs.first['seq'] as int;
      if (seqAfter != seqBefore) {
        // New crud data may have been uploaded since we got the checkpoint. Abort.
        return false;
      }

      await tx.execute(
          "UPDATE ps_buckets SET target_op = CAST(? as INTEGER) WHERE name='\$local'",
          [opId]);

      return true;
      // Flush here - don't want to lose the write checkpoint updates.
    }, flush: true);
  }

  Future<CrudEntry?> nextCrudItem() async {
    var next = await _internalDb
        .getOptional('SELECT * FROM ps_crud ORDER BY id ASC LIMIT 1');
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

    final rows =
        await select('SELECT * FROM ps_crud ORDER BY id ASC LIMIT ?', [limit]);
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
        complete: ({String? writeCheckpoint}) async {
          await writeTransaction((tx) async {
            await tx
                .execute('DELETE FROM ps_crud WHERE id <= ?', [last.clientId]);
            if (writeCheckpoint != null &&
                (await tx.execute('SELECT 1 FROM ps_crud LIMIT 1')).isEmpty) {
              await tx.execute(
                  'UPDATE ps_buckets SET target_op = CAST(? as INTEGER) WHERE name=\'\$local\'',
                  [writeCheckpoint]);
            } else {
              await tx.execute(
                  'UPDATE ps_buckets SET target_op = $maxOpId WHERE name=\'\$local\'');
            }
            // Flush here - don't want to lose the write checkpoint updates.
          }, flush: true);
        });
  }

  Future<String> control(String op, [Object? payload]) async {
    return await writeTransaction(
      (tx) async {
        final [row] =
            await tx.execute('SELECT powersync_control(?, ?)', [op, payload]);
        return row.columnAt(0) as String;
      },
      // We flush when powersync_control yields an instruction to do so.
      flush: false,
    );
  }

  Future<void> flushFileSystem() async {
    // Noop outside of web.
  }

  /// Note: The asynchronous nature of this is due to this needing a global
  /// lock. The actual database operations are still synchronous, and it
  /// is assumed that multiple functions on this instance won't be called
  /// concurrently.
  Future<T> writeTransaction<T>(
      Future<T> Function(SqliteWriteContext tx) callback,
      {Duration? lockTimeout,
      required bool flush}) async {
    return _internalDb.writeTransaction(callback, lockTimeout: lockTimeout);
  }
}
