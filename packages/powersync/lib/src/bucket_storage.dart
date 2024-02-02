import 'dart:async';
import 'dart:convert';

import 'package:collection/collection.dart';
import 'package:powersync/sqlite_async.dart';
import 'package:sqlite_async/sqlite3_common.dart' as sqlite;
import 'package:sqlite_async/sqlite_async.dart';

import 'crud.dart';
import 'schema_helpers.dart';
import 'sync_types.dart';
import 'uuid.dart';
import 'log_internal.dart';

const compactOperationInterval = 1000;

class BucketStorage {
  final SqliteConnection _internalDb;
  bool _hasCompletedSync = false;
  bool _pendingBucketDeletes = false;
  Set<String> tableNames = {};
  int _compactCounter = compactOperationInterval;
  ChecksumCache? _checksumCache;
  late Future<void> _isInitialized;

  BucketStorage(SqliteConnection db) : _internalDb = db {
    _isInitialized = _init();
  }

  _init() async {
    final existingTableRows = await select(
        "SELECT name FROM sqlite_master WHERE type='table' AND name GLOB 'ps_data_*'");
    for (final row in existingTableRows) {
      tableNames.add(row['name'] as String);
    }
  }

  initialized() {
    return _isInitialized;
  }

  // Use only for read statements
  Future<sqlite.ResultSet> select(String query,
      [List<Object?> parameters = const []]) async {
    return _internalDb.execute(query, parameters);
  }

  void startSession() {
    _checksumCache = null;
  }

  Future<List<BucketState>> getBucketStates() async {
    final rows = await select(
        'SELECT name as bucket, cast(last_op as TEXT) as op_id FROM ps_buckets WHERE pending_delete = 0');
    return [
      for (var row in rows)
        BucketState(bucket: row['bucket'], opId: row['op_id'])
    ];
  }

  Future<void> saveSyncData(SyncDataBatch batch) async {
    var count = 0;

    await writeTransaction((tx) async {
      for (var b in batch.buckets) {
        var bucket = b.bucket;
        var data = b.data;

        count += data.length;
        final isFinal = !b.hasMore;
        await _updateBucket(tx, bucket, data, isFinal);
      }
    });
    _compactCounter += count;
  }

  Future<void> _updateBucket(SqliteWriteContext tx, String bucket,
      List<OplogEntry> data, bool finalBucketUpdate) async {
    if (data.isEmpty) {
      return;
    }

    String? lastOp;
    String? firstOp;
    BigInt? targetOp;

    List<Map<String, dynamic>> inserts = [];
    Map<String, Map<String, dynamic>> lastInsert = {};
    List<String> allEntries = [];

    List<SqliteOp> clearOps = [];

    for (final op in data) {
      lastOp = op.opId;
      firstOp ??= op.opId;

      final Map<String, dynamic> insert = {
        'op_id': op.opId,
        'op': op.op!.value,
        'bucket': bucket,
        'key': op.key,
        'row_type': op.rowType,
        'row_id': op.rowId,
        'data': op.data,
        'checksum': op.checksum,
        'superseded': 0
      };

      if (op.op == OpType.move) {
        insert['superseded'] = 1;
      }

      if (op.op == OpType.put ||
          op.op == OpType.remove ||
          op.op == OpType.move) {
        inserts.add(insert);
      }

      if (op.op == OpType.put || op.op == OpType.remove) {
        final key = op.key;
        final prev = lastInsert[key];
        if (prev != null) {
          prev['superseded'] = 1;
        }
        lastInsert[key] = insert;
        allEntries.add(key);
      } else if (op.op == OpType.move) {
        final target = op.parsedData?['target'] as String?;
        if (target != null) {
          final l = BigInt.parse(target, radix: 10);
          if (targetOp == null || l < targetOp) {
            targetOp = l;
          }
        }
      } else if (op.op == OpType.clear) {
        // Any remaining PUT operations should get an implicit REMOVE.
        clearOps.add(SqliteOp(
            "UPDATE ps_oplog SET op=${OpType.remove.value}, data=NULL, hash=0 WHERE (op=${OpType.put.value} OR op=${OpType.remove.value}) AND bucket=? AND op_id <= ?",
            [bucket, op.opId]));
        // And we need to re-apply all of those.
        // We also replace the checksum with the checksum of the CLEAR op.
        clearOps.add(SqliteOp(
            "UPDATE ps_buckets SET last_applied_op = 0, add_checksum = ? WHERE name = ?",
            [op.checksum, bucket]));
      }
    }

    // Mark old ops as superseded
    await tx.execute("""
    UPDATE ps_oplog AS oplog
    SET superseded = 1,
    op = ${OpType.move.value},
    data = NULL
    WHERE oplog.superseded = 0
    AND unlikely(oplog.bucket = ?)
    AND oplog.key IN (SELECT json_each.value FROM json_each(?))
    """, [bucket, jsonEncode(allEntries)]);

    await tx.executeBatch(
        'INSERT INTO ps_oplog(op_id, op, bucket, key, row_type, row_id, data, hash, superseded) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)',
        inserts
            .map((insert) => [
                  insert['op_id'],
                  insert['op'],
                  insert['bucket'],
                  insert['key'],
                  insert['row_type'],
                  insert['row_id'],
                  insert['data'],
                  insert['checksum'],
                  insert['superseded']
                ])
            .toList());

    await tx
        .execute("INSERT OR IGNORE INTO ps_buckets(name) VALUES(?)", [bucket]);

    if (lastOp != null) {
      await tx.execute(
          "UPDATE ps_buckets SET last_op = ? WHERE name = ?", [lastOp, bucket]);
    }
    if (targetOp != null) {
      await tx.execute(
          "UPDATE ps_buckets AS buckets SET target_op = MAX(?, buckets.target_op) WHERE name = ?",
          [targetOp.toString(), bucket]);
    }

    for (final op in clearOps) {
      await tx.execute(op.sql, op.args);
    }

    // Compact superseded ops immediately, but only _after_ clearing
    if (firstOp != null && lastOp != null) {
      await tx.execute("""UPDATE ps_buckets AS buckets
    SET add_checksum = add_checksum + (SELECT IFNULL(SUM(hash), 0)
    FROM ps_oplog AS oplog
    WHERE superseded = 1
    AND oplog.bucket = ?
    AND oplog.op_id >= ?
    AND oplog.op_id <= ?)
    WHERE buckets.name = ?""", [bucket, firstOp, lastOp, bucket]);

      await tx.execute("""DELETE
              FROM ps_oplog
              WHERE superseded = 1
              AND bucket = ?
              AND op_id >= ?
              AND op_id <= ?""", [bucket, firstOp, lastOp]);
    }
  }

  Future<void> removeBuckets(List<String> buckets) async {
    for (final bucket in buckets) {
      await deleteBucket(bucket);
    }
  }

  Future<void> deleteBucket(String bucket) async {
    final newName = "\$delete_${bucket}_${uuid.v4()}";

    await writeTransaction((tx) async {
      await tx.execute(
          "UPDATE ps_oplog SET op=${OpType.remove.value}, data=NULL WHERE op=${OpType.put.value} AND superseded=0 AND bucket=?",
          [bucket]);
      // Rename bucket
      await tx.execute(
          "UPDATE ps_oplog SET bucket=? WHERE bucket=?", [newName, bucket]);
      await tx.execute("DELETE FROM ps_buckets WHERE name = ?", [bucket]);
      await tx.execute(
          "INSERT INTO ps_buckets(name, pending_delete, last_op) SELECT ?, 1, IFNULL(MAX(op_id), 0) FROM ps_oplog WHERE bucket = ?",
          [newName, newName]);
    });

    _pendingBucketDeletes = true;
  }

  Future<bool> hasCompletedSync() async {
    if (_hasCompletedSync) {
      return true;
    }
    final rs = await select(
        "SELECT name, last_applied_op FROM ps_buckets WHERE last_applied_op > 0 LIMIT 1");
    if (rs.isNotEmpty) {
      _hasCompletedSync = true;
      return true;
    }
    return false;
  }

  Future<SyncLocalDatabaseResult> syncLocalDatabase(
      Checkpoint checkpoint) async {
    final r = await validateChecksums(checkpoint);

    if (!r.checkpointValid) {
      for (String b in r.checkpointFailures ?? []) {
        await deleteBucket(b);
      }
      return r;
    }
    final bucketNames = [for (final c in checkpoint.checksums) c.bucket];

    await writeTransaction((tx) async {
      await tx.execute(
          "UPDATE ps_buckets SET last_op = ? WHERE name IN (SELECT json_each.value FROM json_each(?))",
          [checkpoint.lastOpId, jsonEncode(bucketNames)]);
      if (checkpoint.writeCheckpoint != null) {
        await tx.execute(
            "UPDATE ps_buckets SET last_op = ? WHERE name = '\$local'",
            [checkpoint.writeCheckpoint]);
      }
    });

    final valid = await updateObjectsFromBuckets(checkpoint);
    if (!valid) {
      return SyncLocalDatabaseResult(ready: false);
    }

    await forceCompact();

    return SyncLocalDatabaseResult(ready: true);
  }

  Future<bool> updateObjectsFromBuckets(Checkpoint checkpoint) async {
    return writeTransaction((tx) async {
      if (!(await _canUpdateLocal(tx))) {
        return false;
      }

      // Updated objects
      // TODO: Reduce memory usage
      // Some options here:
      // 1. Create a VIEW objects_updates, which contains triggers to update individual tables.
      //    This works well for individual tables, but difficult to have a catch all for untyped data,
      //    and performance degrades when we have hundreds of object types.
      // 2. Similar, but use a TEMP TABLE instead. We can then query those from JS, and populate the tables from JS.
      // 3. Skip the temp table, and query the data directly. Sorting and limiting becomes tricky.
      // 3a. LIMIT on the first oplog step. This prevents us from using JOIN after this.
      // 3b. LIMIT after the second oplog query

      // QUERY PLAN
      // |--SCAN buckets
      // |--SEARCH b USING INDEX ps_oplog_by_opid (bucket=? AND op_id>?)
      // |--SEARCH r USING INDEX ps_oplog_by_row (row_type=? AND row_id=?)
      // `--USE TEMP B-TREE FOR GROUP BY
      // language=DbSqlite
      var opRows = await tx.execute(
          """-- 3. Group the objects from different buckets together into a single one (ops).
         SELECT r.row_type as type,
                r.row_id as id,
                r.data as data,
                json_group_array(r.bucket) FILTER (WHERE r.op=${OpType.put.value}) as buckets,
                /* max() affects which row is used for 'data' */
                max(r.op_id) FILTER (WHERE r.op=${OpType.put.value}) as op_id
         -- 1. Filter oplog by the ops added but not applied yet (oplog b).
         FROM ps_buckets AS buckets
                CROSS JOIN ps_oplog AS b ON b.bucket = buckets.name
              AND (b.op_id > buckets.last_applied_op)
                -- 2. Find *all* current ops over different buckets for those objects (oplog r).
                INNER JOIN ps_oplog AS r
                           ON r.row_type = b.row_type
                             AND r.row_id = b.row_id
         WHERE r.superseded = 0
           AND b.superseded = 0
         -- Group for (3)
         GROUP BY r.row_type, r.row_id
        """);

      await saveOps(tx, opRows);

      await tx.execute("""UPDATE ps_buckets
                SET last_applied_op = last_op
                WHERE last_applied_op != last_op""");

      isolateLogger.fine('Applied checkpoint ${checkpoint.lastOpId}');
      return true;
    });
  }

  // { type: string; id: string; data: string; buckets: string; op_id: string }[]
  Future<void> saveOps(SqliteWriteContext tx, List<sqlite.Row> rows) async {
    Map<String, List<sqlite.Row>> byType = {};
    for (final row in rows) {
      byType.putIfAbsent(row['type'], () => []).add(row);
    }

    for (final entry in byType.entries) {
      final type = entry.key;
      final typeRows = entry.value;
      final table = _getTypeTableName(type);

      // Note that "PUT" and "DELETE" are split, and not applied in row order.
      // So we only do either PUT or DELETE for each individual object, not both.
      final Set<String> removeIds = {};
      List<sqlite.Row> puts = [];
      for (final row in typeRows) {
        if (row['buckets'] == '[]') {
          removeIds.add(row['id']);
        } else {
          puts.add(row);
          removeIds.remove(row['id']);
        }
      }

      puts = puts.where((update) => !removeIds.contains(update['id'])).toList();

      if (tableNames.contains(table)) {
        await tx.execute("""REPLACE INTO "$table"(id, data)
               SELECT json_extract(json_each.value, '\$.id'),
                      json_extract(json_each.value, '\$.data')
               FROM json_each(?)""", [jsonEncode(puts)]);

        await tx.execute("""DELETE
        FROM "$table"
        WHERE id IN (SELECT json_each.value FROM json_each(?))""", [
          jsonEncode([...removeIds])
        ]);
      } else {
        await tx.execute(r"""REPLACE INTO ps_untyped(type, id, data)
        SELECT ?,
      json_extract(json_each.value, '$.id'),
      json_extract(json_each.value, '$.data')
    FROM json_each(?)""", [type, jsonEncode(puts)]);

        await tx.execute("""DELETE FROM ps_untyped
    WHERE type = ?
    AND id IN (SELECT json_each.value FROM json_each(?))""",
            [type, jsonEncode(removeIds.toList())]);
      }
    }
  }

  Future<bool> _canUpdateLocal(SqliteWriteContext tx) async {
    final invalidBuckets = await tx.execute(
        "SELECT name, CAST(target_op AS TEXT), last_op, last_applied_op FROM ps_buckets WHERE target_op > last_op AND (name = '\$local' OR pending_delete = 0)");
    if (invalidBuckets.isNotEmpty) {
      if (invalidBuckets.first['name'] == '\$local') {
        isolateLogger.fine('Waiting for local changes to be acknowledged');
      } else {
        isolateLogger.fine('Waiting for more data: $invalidBuckets');
      }
      return false;
    }
    // This is specifically relevant for when data is added to crud before another batch is completed.
    final rows = await tx.execute('SELECT 1 FROM ps_crud LIMIT 1');
    if (rows.isNotEmpty) {
      return false;
    }
    return true;
  }

  Future<SyncLocalDatabaseResult> validateChecksums(
      Checkpoint checkpoint) async {
    final rows = await select("""WITH
     bucket_list(bucket, lower_op_id) AS (
         SELECT
                json_extract(json_each.value, '\$.bucket') as bucket,
                json_extract(json_each.value, '\$.last_op_id') as lower_op_id
         FROM json_each(?)
         )
      SELECT
         buckets.name as bucket,
         buckets.add_checksum as add_checksum,
         IFNULL(SUM(oplog.hash), 0) as oplog_checksum,
         COUNT(oplog.op_id) as count,
         CAST(MAX(oplog.op_id) as TEXT) as last_op_id,
         CAST(buckets.last_applied_op as TEXT) as last_applied_op
       FROM bucket_list
         LEFT OUTER JOIN ps_buckets AS buckets ON
             buckets.name = bucket_list.bucket
         LEFT OUTER JOIN ps_oplog AS oplog ON
             bucket_list.bucket = oplog.bucket AND
             oplog.op_id <= ? AND oplog.op_id > bucket_list.lower_op_id
       GROUP BY bucket_list.bucket""", [
      jsonEncode(checkpoint.checksums
          .map((checksum) => {
                'bucket': checksum.bucket,
                'last_op_id':
                    _checksumCache?.checksums[checksum.bucket]?.lastOpId ?? '0'
              })
          .toList()),
      checkpoint.lastOpId
    ]);

    Map<String, BucketChecksum> byBucket = {};
    if (_checksumCache != null) {
      final checksums = _checksumCache!.checksums;
      for (var row in rows) {
        final String? bucket = row['bucket'];
        if (bucket == null) {
          continue;
        }
        if (BigInt.parse(row['last_applied_op']) >
            BigInt.parse(_checksumCache!.lastOpId)) {
          throw AssertionError(
              "assertion failed: ${row['last_applied_op']} > ${_checksumCache!.lastOpId}");
        }
        int checksum;
        String? lastOpId = row['last_op_id'];
        if (checksums.containsKey(bucket)) {
          // All rows may have been filtered out, in which case we use the previous one
          lastOpId ??= checksums[bucket]!.lastOpId;
          checksum =
              (checksums[bucket]!.checksum + row['oplog_checksum'] as int)
                  .toSigned(32);
        } else {
          checksum = (row['add_checksum'] + row['oplog_checksum']).toSigned(32);
        }
        byBucket[bucket] = BucketChecksum(
            bucket: bucket,
            checksum: checksum,
            count: row['count'],
            lastOpId: lastOpId);
      }
    } else {
      for (final row in rows) {
        final String? bucket = row['bucket'];
        if (bucket == null) {
          continue;
        }
        final int c1 = row['add_checksum'];
        final int c2 = row['oplog_checksum'];

        final checksum = (c1 + c2).toSigned(32);

        byBucket[bucket] = BucketChecksum(
            bucket: bucket,
            checksum: checksum,
            count: row['count'],
            lastOpId: row['last_op_id']);
      }
    }

    List<String> failedChecksums = [];
    for (final checksum in checkpoint.checksums) {
      final local = byBucket[checksum.bucket] ??
          BucketChecksum(bucket: checksum.bucket, checksum: 0, count: 0);
      // Note: Count is informational only.
      if (local.checksum != checksum.checksum) {
        isolateLogger.warning(
            'Checksum mismatch for ${checksum.bucket}: local ${local.checksum} != remote ${checksum.checksum}. Likely due to sync rule changes.');
        failedChecksums.add(checksum.bucket);
      }
    }
    if (failedChecksums.isEmpty) {
      // FIXME: Checksum cache disabled since it's broken when add_checksum is modified
      // _checksumCache = ChecksumCache(checkpoint.lastOpId, byBucket);
      return SyncLocalDatabaseResult(ready: true);
    } else {
      _checksumCache = null;
      return SyncLocalDatabaseResult(
          ready: false,
          checkpointValid: false,
          checkpointFailures: failedChecksums);
    }
  }

  Future<void> forceCompact() async {
    _compactCounter = compactOperationInterval;
    _pendingBucketDeletes = true;

    await autoCompact();
  }

  Future<void> autoCompact() async {
    // 1. Delete buckets
    await _deletePendingBuckets();

    // 2. Clear REMOVE operations, only keeping PUT ones
    await _clearRemoveOps();

    // await _compactWal();
  }

  // ignore: unused_element
  Future<void> _compactWal() async {
    try {
      await writeTransaction((tx) async {
        tx.execute('PRAGMA wal_checkpoint(TRUNCATE)');
      });
    } on sqlite.SqliteException catch (e) {
      // Ignore SQLITE_BUSY
      if (e.resultCode == 5) {
        // Ignore
      } else if (e.resultCode == 6) {
        // Ignore
      }
    }
  }

  Future<void> _deletePendingBuckets() async {
    if (_pendingBucketDeletes) {
      // Executed once after start-up, and again when there are pending deletes.
      await writeTransaction((tx) async {
        tx.execute(
            'DELETE FROM ps_oplog WHERE bucket IN (SELECT name FROM ps_buckets WHERE pending_delete = 1 AND last_applied_op = last_op AND last_op >= target_op)');
        tx.execute(
            'DELETE FROM ps_buckets WHERE pending_delete = 1 AND last_applied_op = last_op AND last_op >= target_op');
      });
      _pendingBucketDeletes = false;
    }
  }

  Future<void> _clearRemoveOps() async {
    if (_compactCounter < compactOperationInterval) {
      return;
    }

    final rows = await select(
        'SELECT name, cast(last_applied_op as TEXT) as last_applied_op, cast(last_op as TEXT) as last_op FROM ps_buckets WHERE pending_delete = 0');
    for (var row in rows) {
      await writeTransaction((tx) async {
        // Note: The row values here may be different from when queried. That should not be an issue.

        await tx.execute("""UPDATE ps_buckets AS buckets
           SET add_checksum = add_checksum + (SELECT IFNULL(SUM(hash), 0)
                                              FROM ps_oplog AS oplog
                                              WHERE (superseded = 1 OR op != ${OpType.put.value})
                                                AND oplog.bucket = ?
                                                AND oplog.op_id <= ?)
           WHERE buckets.name = ?""",
            [row['name'], row['last_applied_op'], row['name']]);
        await tx.execute(
            """DELETE
           FROM ps_oplog
           WHERE (superseded = 1 OR op != ${OpType.put.value})
             AND bucket = ?
             AND op_id <= ?""",
            // Must use the same values as above
            [row['name'], row['last_applied_op']]);
      });
    }
    _compactCounter = 0;
  }

  void setTargetCheckpoint(Checkpoint checkpoint) {
    // No-op for now
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
        'SELECT seq FROM sqlite_sequence WHERE name = \'ps_crud\'');
    if (rs.isEmpty) {
      // Nothing to update
      return false;
    }
    int seqBefore = rs.first['seq'];
    var opId = await checkpointCallback();

    return await writeTransaction((tx) async {
      final anyData = await tx.execute('SELECT 1 FROM ps_crud LIMIT 1');
      if (anyData.isNotEmpty) {
        return false;
      }
      final rs = await tx
          .execute('SELECT seq FROM sqlite_sequence WHERE name = \'ps_crud\'');
      assert(rs.isNotEmpty);

      int seqAfter = rs.first['seq'];
      if (seqAfter != seqBefore) {
        // New crud data may have been uploaded since we got the checkpoint. Abort.
        return false;
      }

      await tx.execute(
          "UPDATE ps_buckets SET target_op = ? WHERE name='\$local'", [opId]);

      return true;
    });
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
          await writeTransaction((db) async {
            db.execute('DELETE FROM ps_crud WHERE id <= ?', [last.clientId]);
            if (writeCheckpoint != null &&
                (await db.execute('SELECT 1 FROM ps_crud LIMIT 1')).isEmpty) {
              await db.execute(
                  'UPDATE ps_buckets SET target_op = $writeCheckpoint WHERE name=\'\$local\'');
            } else {
              await db.execute(
                  'UPDATE ps_buckets SET target_op = $maxOpId WHERE name=\'\$local\'');
            }
          });
        });
  }

  /// Note: The asynchronous nature of this is due to this needing a global
  /// lock. The actual database operations are still synchronous, and it
  /// is assumed that multiple functions on this instance won't be called
  /// concurrently.
  Future<T> writeTransaction<T>(
      Future<T> Function(SqliteWriteContext tx) callback,
      {Duration? lockTimeout}) async {
    return _internalDb.writeTransaction(callback);
  }
}

class BucketState {
  final String bucket;
  final String opId;

  const BucketState({required this.bucket, required this.opId});

  @override
  String toString() {
    return "BucketState<$bucket:$opId>";
  }

  @override
  int get hashCode {
    return Object.hash(bucket, opId);
  }

  @override
  bool operator ==(Object other) {
    return other is BucketState && other.bucket == bucket && other.opId == opId;
  }
}

class SyncDataBatch {
  List<SyncBucketData> buckets;

  SyncDataBatch(this.buckets);
}

class SyncBucketData {
  final String bucket;
  final List<OplogEntry> data;
  final bool hasMore;
  final String? after;
  final String? nextAfter;

  const SyncBucketData(
      {required this.bucket,
      required this.data,
      this.hasMore = false,
      this.after,
      this.nextAfter});

  SyncBucketData.fromJson(Map<String, dynamic> json)
      : bucket = json['bucket'],
        hasMore = json['has_more'] ?? false,
        after = json['after'],
        nextAfter = json['next_after'],
        data =
            (json['data'] as List).map((e) => OplogEntry.fromJson(e)).toList();
}

class OplogEntry {
  final String opId;

  final OpType? op;

  /// rowType + rowId uniquely identifies an entry in the local database.
  final String? rowType;
  final String? rowId;

  /// Together with rowType and rowId, this uniquely identifies a source entry
  /// per bucket in the oplog. There may be multiple source entries for a single
  /// "rowType + rowId" combination.
  final String? subkey;

  final String? data;
  final int checksum;

  const OplogEntry(
      {required this.opId,
      required this.op,
      this.subkey,
      this.rowType,
      this.rowId,
      this.data,
      required this.checksum});

  OplogEntry.fromJson(Map<String, dynamic> json)
      : opId = json['op_id'],
        op = OpType.fromJson(json['op']),
        rowType = json['object_type'],
        rowId = json['object_id'],
        checksum = json['checksum'],
        data = json['data'] is String ? json['data'] : jsonEncode(json['data']),
        subkey = json['subkey'] is String ? json['subkey'] : null;

  Map<String, dynamic>? get parsedData {
    return data == null ? null : jsonDecode(data!);
  }

  /// Key to uniquely represent a source entry in a bucket.
  /// This is used to supersede old entries.
  /// Relevant for put and remove ops.
  String get key {
    return "$rowType/$rowId/$subkey";
  }
}

class SqliteOp {
  String sql;
  List<dynamic> args;

  SqliteOp(this.sql, this.args);
}

class SyncLocalDatabaseResult {
  final bool ready;
  final bool checkpointValid;
  final List<String>? checkpointFailures;

  const SyncLocalDatabaseResult(
      {this.ready = true,
      this.checkpointValid = true,
      this.checkpointFailures});

  @override
  String toString() {
    return "SyncLocalDatabaseResult<ready=$ready, checkpointValid=$checkpointValid, failures=$checkpointFailures>";
  }

  @override
  int get hashCode {
    return Object.hash(
        ready, checkpointValid, const ListEquality().hash(checkpointFailures));
  }

  @override
  bool operator ==(Object other) {
    return other is SyncLocalDatabaseResult &&
        other.ready == ready &&
        other.checkpointValid == checkpointValid &&
        const ListEquality()
            .equals(other.checkpointFailures, checkpointFailures);
  }
}

class ChecksumCache {
  String lastOpId;
  Map<String, BucketChecksum> checksums;

  ChecksumCache(this.lastOpId, this.checksums);
}

enum OpType {
  clear(1),
  move(2),
  put(3),
  remove(4);

  final int value;

  const OpType(this.value);

  static OpType? fromJson(String json) {
    switch (json) {
      case 'CLEAR':
        return clear;
      case 'MOVE':
        return move;
      case 'PUT':
        return put;
      case 'REMOVE':
        return remove;
      default:
        return null;
    }
  }
}

/// Get a table name for a specific type. The table may or may not exist.
///
/// The table name must always be enclosed in "quotes" when using inside a SQL query.
///
/// @param type
String _getTypeTableName(String type) {
  // Test for invalid characters rather than escaping.
  if (invalidSqliteCharacters.hasMatch(type)) {
    throw AssertionError("Invalid characters in type name: $type");
  }
  return "ps_data__$type";
}
