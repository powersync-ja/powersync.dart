import 'dart:async';
import 'dart:convert';

import './mutex.dart';
import 'package:sqlite3/common.dart';

import './schema.dart';
import './schema_logic.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;
import 'package:uuid/uuid.dart';
import 'package:uuid/uuid_util.dart';

const compactOperationInterval = 1000;

final invalidSqliteCharacters = RegExp('"\'%,\\.#\\s');

const uuid = Uuid(options: {'grng': UuidUtil.cryptoRNG});

class BucketStorage {
  final sqlite.Database _internalDb;
  final Mutex mutex;
  bool _hasCompletedSync = false;
  bool _pendingBucketDeletes = false;
  Set<String> tableNames = {};
  int _compactCounter = compactOperationInterval;
  ChecksumCache? _checksumCache;

  BucketStorage(sqlite.Database db, {required this.mutex}) : _internalDb = db {
    _init();
  }

  _init() {
    final existingTableRows = select(
        "SELECT name FROM sqlite_master WHERE type='table' AND name GLOB 'objects__*'");
    for (final row in existingTableRows) {
      tableNames.add(row['name'] as String);
    }
  }

  // Use only for read statements
  sqlite.ResultSet select(String query, [List<Object?> parameters = const []]) {
    return _internalDb.select(query, parameters);
  }

  void startSession() {
    _checksumCache = null;
  }

  bool canQueryType(String type) {
    return tableNames.contains(_getTableName(type));
  }

  List<BucketState> getBucketStates() {
    final rows = select(
        'SELECT name as bucket, cast(last_op as TEXT) as op_id FROM buckets WHERE pending_delete = 0');
    return [for (var row in rows) BucketState(row['bucket'], row['op_id'])];
  }

  Future<void> saveSyncData(SyncDataBatch batch) async {
    var count = 0;

    await writeTransaction((db) {
      for (var b in batch.buckets) {
        var bucket = b.bucket;
        var data = b.data;

        count += data.length;
        final isFinal = !b.hasMore;
        _updateBucket(db, bucket, data, isFinal);
      }
    });
    _compactCounter += count;
  }

  void _updateBucket(sqlite.Database db, String bucket, List<OplogEntry> data,
      bool finalBucketUpdate) {
    if (data.isEmpty) {
      return;
    }

    String? last_op;
    String? first_op;
    BigInt? target_op;

    List<Map<String, dynamic>> inserts = [];
    Map<String, Map<String, dynamic>> lastInsert = {};
    List<Map<String, dynamic>> allEntries = [];

    List<SqliteOp> clearOps = [];

    for (final op in data) {
      last_op = op.opId;
      first_op ??= op.opId;

      final Map<String, dynamic> insert = {
        'op_id': op.opId,
        'op': op.op!.value,
        'bucket': bucket,
        'object_type': op.objectType,
        'object_id': op.objectId,
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
        final key = '${op.objectType}/${op.objectId}';
        final prev = lastInsert[key];
        if (prev != null) {
          prev['superseded'] = 1;
        }
        lastInsert[key] = insert;
        allEntries.add({'type': op.objectType, 'id': op.objectId});
      } else if (op.op == OpType.move) {
        final target = op.data?['target'] as String?;
        if (target != null) {
          final l = BigInt.parse(target, radix: 10);
          if (target_op == null || l < target_op) {
            target_op = l;
          }
        }
      } else if (op.op == OpType.clear) {
        // Any remaining PUT operations should get an implicit REMOVE.
        clearOps.add(SqliteOp(
            "UPDATE oplog SET op=${OpType.remove.value}, data=NULL, hash=0 WHERE (op=${OpType.put.value} OR op=${OpType.remove.value}) AND bucket=? AND op_id <= ?",
            [bucket, op.opId]));
        // And we need to re-apply all of those.
        // We also replace the checksum with the checksum of the CLEAR op.
        clearOps.add(SqliteOp(
            "UPDATE buckets SET last_applied_op = 0, add_checksum = ? WHERE name = ?",
            [op.checksum, bucket]));
      }
    }

    // Mark old ops as superseded
    db.execute("""
    UPDATE oplog
    SET superseded = 1,
    op = ${OpType.move.value},
    data = NULL
    WHERE oplog.superseded = 0
    AND unlikely(oplog.bucket = ?)
    AND(oplog.object_type, oplog.object_id) IN(
        SELECT json_extract(json_each.value,
        '\$.type'), json_extract(json_each.value, '\$.id')
    FROM json_each(?)
    )
    """, [bucket, jsonEncode(allEntries)]);

    var stmt = db.prepare(
        'INSERT INTO oplog(op_id, op, bucket, object_type, object_id, data, hash, superseded) VALUES (?, ?, ?, ?, ?, ?, ?, ?)');
    try {
      for (var insert in inserts) {
        stmt.execute([
          insert['op_id'],
          insert['op'],
          insert['bucket'],
          insert['object_type'],
          insert['object_id'],
          insert['data'] == null ? null : jsonEncode(insert['data']),
          insert['checksum'],
          insert['superseded']
        ]);
      }
    } finally {
      stmt.dispose();
    }

    db.execute("INSERT OR IGNORE INTO buckets(name) VALUES(?)", [bucket]);

    if (last_op != null) {
      db.execute(
          "UPDATE buckets SET last_op = ? WHERE name = ?", [last_op, bucket]);
    }
    if (target_op != null) {
      db.execute(
          "UPDATE buckets SET target_op = MAX(?, buckets.target_op) WHERE name = ?",
          [target_op.toString(), bucket]);
    }

    for (final op in clearOps) {
      db.execute(op.sql, op.args);
    }

    // Compact superseded ops immediately, but only _after_ clearing
    if (first_op != null && last_op != null) {
      db.execute("""UPDATE buckets
    SET add_checksum = add_checksum + (SELECT IFNULL(SUM(hash), 0)
    FROM oplog
    WHERE superseded = 1
    AND oplog.bucket = ?
    AND oplog.op_id >= ?
    AND oplog.op_id <= ?)
    WHERE buckets.name = ?""", [bucket, first_op, last_op, bucket]);

      db.execute("""DELETE
              FROM oplog
              WHERE superseded = 1
              AND bucket = ?
              AND op_id >= ?
              AND op_id <= ?""", [bucket, first_op, last_op]);
    }
  }

  Future<void> removeBuckets(List<String> buckets) async {
    for (final bucket in buckets) {
      await deleteBucket(bucket);
    }
  }

  Future<void> deleteBucket(String bucket) async {
    final newName = "\$delete_${bucket}_${uuid.v4()}";

    await writeTransaction((db) {
      db.execute(
          "UPDATE oplog SET op=${OpType.remove.value}, data=NULL WHERE op=${OpType.put.value} AND superseded=0 AND bucket=?",
          [bucket]);
      // Rename bucket
      db.execute("UPDATE oplog SET bucket=? WHERE bucket=?", [newName, bucket]);
      db.execute("DELETE FROM buckets WHERE name = ?", [bucket]);
      db.execute(
          "INSERT INTO buckets(name, pending_delete, last_op) SELECT ?, 1, IFNULL(MAX(op_id), 0) FROM oplog WHERE bucket = ?",
          [newName, newName]);
    });

    _pendingBucketDeletes = true;
  }

  bool hasCompletedSync() {
    if (_hasCompletedSync) {
      return true;
    }
    final rs = select(
        "SELECT name, last_applied_op FROM buckets WHERE last_applied_op > 0 LIMIT 1");
    if (rs.isNotEmpty) {
      _hasCompletedSync = true;
      return true;
    }
    return false;
  }

  Future<SyncLocalDatabaseResult> syncLocalDatabase(
      Checkpoint checkpoint) async {
    final r = validateChecksums(checkpoint);

    if (!r.checkpointValid) {
      for (String b in r.checkpointFailures ?? []) {
        deleteBucket(b);
      }
      return r;
    }
    final bucketNames = [
      '\$local',
      for (final c in checkpoint.checksums) c.bucket
    ];

    await writeTransaction((db) {
      db.execute(
          "UPDATE buckets SET last_op = ? WHERE name IN (SELECT json_each.value FROM json_each(?))",
          [checkpoint.lastOpId, jsonEncode(bucketNames)]);
    });

    final valid = await updateObjectsFromBuckets(checkpoint);
    if (!valid) {
      return SyncLocalDatabaseResult(false, true, null);
    }

    await forceCompact();

    return SyncLocalDatabaseResult(true, true, null);
  }

  Future<bool> updateObjectsFromBuckets(Checkpoint checkpoint) async {
    return writeTransaction((db) {
      if (!_canUpdateLocal(db)) {
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
      // |--SEARCH b USING INDEX sqlite_autoindex_oplog_1 (bucket=? AND op_id>?)
      // |--SEARCH r USING INDEX oplog_by_object (object_type=? AND object_id=?)
      // `--USE TEMP B-TREE FOR GROUP BY
      // language=DbSqlite
      var stmt = db.prepare(
          """-- 3. Group the objects from different buckets together into a single one (ops).
         SELECT r.object_type as type,
                r.object_id as id,
                r.data as data,
                json_group_array(r.bucket) FILTER (WHERE r.op=${OpType.put.value}) as buckets,
                /* max() affects which row is used for 'data' */
                max(r.op_id) FILTER (WHERE r.op=${OpType.put.value}) as op_id
         -- 1. Filter oplog by the ops added but not applied yet (oplog b).
         FROM buckets
                CROSS JOIN oplog b ON b.bucket = buckets.name
              AND (b.op_id > buckets.last_applied_op)
                -- 2. Find *all* current ops over different buckets for those objects (oplog r).
                INNER JOIN oplog r
                           ON r.object_type = b.object_type
                             AND r.object_id = b.object_id
         WHERE r.superseded = 0
           AND b.superseded = 0
         -- Group for (3)
         GROUP BY r.object_type, r.object_id
        """);
      try {
        // TODO: Perhaps we don't need batching for this?
        var cursor = stmt.selectCursor([]);
        List<sqlite.Row> rows = [];
        while (cursor.moveNext()) {
          var row = cursor.current;
          rows.add(row);

          if (rows.length >= 10000) {
            saveOps(db, rows);
            rows = [];
          }
        }
        if (rows.isNotEmpty) {
          saveOps(db, rows);
        }
      } finally {
        stmt.dispose();
      }

      db.execute("""UPDATE buckets
                SET last_applied_op = last_op
                WHERE last_applied_op != last_op""");

      print('${DateTime.now()} Updated local state');
      return true;
    });
  }

  // { type: string; id: string; data: string; buckets: string; op_id: string }[]
  void saveOps(sqlite.Database db, List<sqlite.Row> rows) {
    Map<String, List<sqlite.Row>> byType = {};
    for (final row in rows) {
      byType.putIfAbsent(row['type'], () => []).add(row);
    }

    for (final entry in byType.entries) {
      final type = entry.key;
      final typeRows = entry.value;
      final table = _getTableName(type);

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
        db.execute("""REPLACE INTO "$table"(id, data)
               SELECT json_extract(json_each.value, '\$.id'),
                      json_extract(json_each.value, '\$.data')
               FROM json_each(?)""", [jsonEncode(puts)]);

        db.execute("""DELETE
        FROM "$table"
        WHERE id IN (SELECT json_each.value FROM json_each(?))""", [
          jsonEncode([...removeIds])
        ]);
      } else {
        db.execute(r"""REPLACE INTO objects_untyped(type, id, data)
        SELECT ?,
      json_extract(json_each.value, '$.id'),
      json_extract(json_each.value, '$.data')
    FROM json_each(?)""", [type, jsonEncode(puts)]);

        db.execute("""DELETE FROM objects_untyped
    WHERE type = ?
    AND id IN (SELECT json_each.value FROM json_each(?))""",
            [type, jsonEncode(removeIds.toList())]);
      }
    }
  }

  bool _canUpdateLocal(sqlite.Database db) {
    final invalidBuckets = db.select(
        "SELECT name, target_op, last_op, last_applied_op FROM buckets WHERE target_op > last_op AND (name = '\$local' OR pending_delete = 0)");
    if (invalidBuckets.isNotEmpty) {
      print('cant update local: $invalidBuckets');
      return false;
    }
    // This is specifically relevant for when data is added to crud before another batch is completed.
    final rows = db.select('SELECT 1 FROM crud LIMIT 1');
    if (rows.isNotEmpty) {
      return false;
    }
    return true;
  }

  SyncLocalDatabaseResult validateChecksums(Checkpoint checkpoint) {
    final rows = select("""WITH
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
         LEFT OUTER JOIN buckets ON
             buckets.name = bucket_list.bucket
         LEFT OUTER JOIN oplog ON
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
        final bucket = row['bucket'];
        if (BigInt.parse(row['last_applied_op']) >
            BigInt.parse(_checksumCache!.lastOpId)) {
          throw AssertionError(
              "assertion failed: ${row['last_applied_op']} > ${_checksumCache!.lastOpId}");
        }
        int checksum;
        String? last_op_id = row['last_op_id'];
        if (checksums.containsKey(bucket)) {
          // All rows may have been filtered out, in which case we use the previous one
          last_op_id ??= checksums[bucket]!.lastOpId;
          checksum =
              (checksums[bucket]!.checksum + row['oplog_checksum'] as int)
                  .toSigned(32);
        } else {
          checksum = (row['add_checksum'] + row['oplog_checksum']).toSigned(32);
        }
        byBucket[bucket] = BucketChecksum(bucket, checksum, row['count'])
          ..lastOpId = last_op_id;
      }
    } else {
      for (final row in rows) {
        final bucket = row['bucket'];
        final int c1 = row['add_checksum'];
        final int c2 = row['oplog_checksum'];

        final checksum = (c1 + c2).toSigned(32);

        byBucket[bucket] = BucketChecksum(bucket, checksum, row['count'])
          ..lastOpId = row['last_op_id'];
      }
    }

    List<String> failedChecksums = [];
    for (final checksum in checkpoint.checksums) {
      final local =
          byBucket[checksum.bucket] ?? BucketChecksum(checksum.bucket, 0, 0);
      // Note: Count is informational only.
      if (local.checksum != checksum.checksum) {
        print(
            "Checksum failed: local ${local.checksum} != remote ${checksum.checksum}");
        failedChecksums.add(checksum.bucket);
      }
    }
    if (failedChecksums.isEmpty) {
      // FIXME: Checksum cache disabled since it's broken when add_checksum is modified
      // _checksumCache = ChecksumCache(checkpoint.lastOpId, byBucket);
      return SyncLocalDatabaseResult(true, true, null);
    } else {
      _checksumCache = null;
      print("Checksums failed: ${failedChecksums}");
      return SyncLocalDatabaseResult(false, false, failedChecksums);
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

    // await _compact();
  }

  Future<void> _compact() async {
    try {
      await writeTransaction((db) {
        db.select('PRAGMA wal_checkpoint(TRUNCATE)');
      });
    } on SqliteException catch (e) {
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
      await writeTransaction((db) {
        db.execute(
            'DELETE FROM oplog WHERE bucket IN (SELECT name FROM buckets WHERE pending_delete = 1 AND last_applied_op = last_op AND last_op >= target_op)');
        db.execute(
            'DELETE FROM buckets WHERE pending_delete = 1 AND last_applied_op = last_op AND last_op >= target_op');
      });
      _pendingBucketDeletes = false;
    }
  }

  Future<void> _clearRemoveOps() async {
    if (_compactCounter < compactOperationInterval) {
      return;
    }

    final rows = select(
        'SELECT name, cast(last_applied_op as TEXT) as last_applied_op, cast(last_op as TEXT) as last_op FROM buckets WHERE pending_delete = 0');
    for (var row in rows) {
      await writeTransaction((db) {
        // Note: The row values here may be different from when queried. That should not be an issue.

        db.execute("""UPDATE buckets
           SET add_checksum = add_checksum + (SELECT IFNULL(SUM(hash), 0)
                                              FROM oplog
                                              WHERE (superseded = 1 OR op != ${OpType.put.value})
                                                AND oplog.bucket = ?
                                                AND oplog.op_id <= ?)
           WHERE buckets.name = ?""",
            [row['name'], row['last_applied_op'], row['name']]);
        db.execute(
            """DELETE
           FROM oplog
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
    final rs1 = select(
        'SELECT target_op FROM buckets WHERE name = \'\$local\' AND target_op = $maxOpId');
    if (rs1.isEmpty) {
      // Nothing to update
      return false;
    }
    final rs = select('SELECT seq FROM sqlite_sequence WHERE name = \'crud\'');
    if (rs.isEmpty) {
      // Nothing to update
      return false;
    }
    int seqBefore = rs.first['seq'];
    var opId = await checkpointCallback();

    return await writeTransaction((tx) {
      final anyData = tx.select('SELECT 1 FROM crud LIMIT 1');
      if (anyData.isNotEmpty) {
        return false;
      }
      final rs =
          tx.select('SELECT seq FROM sqlite_sequence WHERE name = \'crud\'');
      assert(rs.isNotEmpty);

      int seqAfter = rs.first['seq'];
      if (seqAfter != seqBefore) {
        // New crud data may have been uploaded since we got the checkpoint. Abort.
        return false;
      }

      tx.select(
          "UPDATE buckets SET target_op = ? WHERE name='\$local'", [opId]);

      return true;
    });
  }

  bool hasCrud() {
    final anyData = select('SELECT 1 FROM crud LIMIT 1');
    return anyData.isNotEmpty;
  }

  CrudBatch? getCrudBatch({limit = 100}) {
    if (!hasCrud()) {
      return null;
    }

    final rows = select('SELECT * FROM crud ORDER BY id ASC LIMIT ?', [limit]);
    List<dynamic> all = [];
    for (var row in rows) {
      final data = jsonDecode(row['data']);
      final id = row['id'];
      all.add({...data, 'op_id': id});
    }
    if (all.isEmpty) {
      return null;
    }
    final last = all[all.length - 1];
    return CrudBatch(
        crud: all,
        haveMore: true,
        complete: () async {
          await writeTransaction((db) {
            db.execute('DELETE FROM crud WHERE id <= ?', [last['op_id']]);
            db.execute(
                'UPDATE buckets SET target_op = $maxOpId WHERE name=\'\$local\'');
          });
        });
  }

  /// Note: The asynchronous nature of this is due to this needing a global
  /// lock. The actual database operations are still synchronous, and it
  /// is assumed that multiple functions on this instance won't be called
  /// concurrently.
  Future<T> writeTransaction<T>(
      FutureOr<T> Function(sqlite.Database tx) callback,
      {Duration? lockTimeout}) async {
    return mutex.lock(() async {
      final r = await asyncTransaction(_internalDb, callback);
      return r;
    });
  }
}

class CrudBatch {
  List<dynamic> crud;
  bool haveMore;
  Future<void> Function() complete;

  CrudBatch(
      {required this.crud, required this.haveMore, required this.complete});
}

Future<T> asyncTransaction<T>(sqlite.Database db,
    FutureOr<T> Function(sqlite.Database db) callback) async {
  for (var i = 50; i >= 0; i--) {
    try {
      db.execute('BEGIN IMMEDIATE');
      late T result;
      try {
        result = await callback(db);
        db.execute('COMMIT');
      } catch (e) {
        try {
          db.execute('ROLLBACK');
        } catch (e2) {}
        rethrow;
      }

      return result;
    } catch (e) {
      if (e is sqlite.SqliteException) {
        if (e.resultCode == 5 && i != 0) {
          // SQLITE_BUSY
          await Future.delayed(const Duration(milliseconds: 50));
          continue;
        }
      }
      rethrow;
    }
  }
  throw AssertionError('Should not reach this');
}

class BucketState {
  final String bucket;
  final String opId;

  BucketState(this.bucket, this.opId);
}

class SyncDataBatch {
  List<SyncBucketData> buckets;

  SyncDataBatch(this.buckets);
}

class SyncBucketData {
  String bucket;
  List<OplogEntry> data;
  bool hasMore;
  String after;
  String nextAfter;

  SyncBucketData(
      this.bucket, this.data, this.hasMore, this.after, this.nextAfter);

  SyncBucketData.fromJson(Map<String, dynamic> json)
      : bucket = json['bucket'],
        hasMore = json['has_more'] ?? false,
        after = json['after'],
        nextAfter = json['next_after'],
        data =
            (json['data'] as List).map((e) => OplogEntry.fromJson(e)).toList();
}

class OplogEntry {
  String opId;
  OpType? op;
  String? objectType;
  String? objectId;
  Map<String, dynamic>? data;
  int checksum;

  OplogEntry(this.opId, this.op, this.objectType, this.objectId, this.data,
      this.checksum);

  OplogEntry.fromJson(Map<String, dynamic> json)
      : opId = json['op_id'],
        op = OpType.fromJson(json['op']),
        objectType = json['object_type'],
        objectId = json['object_id'],
        checksum = json['checksum'],
        data = json['data'];
}

class SqliteOp {
  String sql;
  List<dynamic> args;

  SqliteOp(this.sql, this.args);
}

class Checkpoint {
  String lastOpId;
  List<BucketChecksum> checksums;

  Checkpoint(this.lastOpId, this.checksums);

  Checkpoint.fromJson(Map<String, dynamic> json)
      : lastOpId = json['last_op_id'],
        checksums = (json['buckets'] as List)
            .map((b) => BucketChecksum.fromJson(b))
            .toList();
}

class BucketChecksum {
  String bucket;
  int checksum;
  int count;
  String? lastOpId;

  BucketChecksum(this.bucket, this.checksum, this.count);

  BucketChecksum.fromJson(Map<String, dynamic> json)
      : bucket = json['bucket'],
        checksum = json['checksum'],
        count = json['count'],
        lastOpId = json['last_op_id'];
}

class SyncLocalDatabaseResult {
  bool ready;
  bool checkpointValid;
  List<String>? checkpointFailures;

  SyncLocalDatabaseResult(
      this.ready, this.checkpointValid, this.checkpointFailures);
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

List<String> updateSchema(sqlite.Database db, Schema schema) {
  List<String> secondaryConnectionOps = [];

  secondaryConnectionOps = [];
  final types = schema.tables.map((table) => table.name).toList();
  _createTablesAndTriggersOps(db, types);

  for (var model in schema.tables) {
    var createViewOp = createViewStatement(model);
    secondaryConnectionOps.add(createViewOp);
    db.execute(createViewOp);
    for (final op in createViewTriggerStatements(model)) {
      secondaryConnectionOps.add(op);
      db.execute(op);
    }
  }

  return secondaryConnectionOps;
}

Set<String> _createTablesAndTriggersOps(
    sqlite.Database db, List<String> types) {
  // Make sure to refresh tables in the same transaction as updating them
  Set<String> tableNames = {};
  final existingTableRows = db.select(
      "SELECT name FROM sqlite_master WHERE type='table' AND name GLOB 'objects__*'");
  for (final row in existingTableRows) {
    tableNames.add(row['name'] as String);
  }
  final Set<String> remainingTables = {...tableNames};
  final Set<String> updatedTableList = {};
  final List<String> addedTypes = [];

  for (final type in types) {
    final tableName = _getTableName(type);
    updatedTableList.add(tableName);
    final exists = remainingTables.contains(tableName);
    remainingTables.remove(tableName);
    if (exists) {
      continue;
    }
    addedTypes.add(type);

    db.execute("""CREATE TABLE "${tableName}"
    (
    id   TEXT,
    data TEXT,
    PRIMARY KEY (id)
    )""");
    db.execute("""INSERT INTO "${tableName}"(id, data)
    SELECT id, data
    FROM objects_untyped
    WHERE type = ?""", [type]);
    db.execute("""DELETE
    FROM objects_untyped
    WHERE type = ?""", [type]);
  }

  for (final tableName in remainingTables) {
    final typeMatch = RegExp("^objects__(.+)\$").firstMatch(tableName);
    if (typeMatch == null) {
      continue;
    }
    final type = typeMatch[1];
    db.execute(
        'INSERT INTO objects_untyped(type, id, data) SELECT ?, id, data FROM "${tableName}"',
        [type]);
    db.execute('DROP TABLE "${tableName}"');
  }

  return updatedTableList;
}

/// Get a table name for a specific type. The table may or may not exist.
///
/// The table name must always be enclosed in "quotes" when using inside a SQL query.
///
/// @param type
_getTableName(String type) {
  // Test for invalid characters rather than escaping.
  if (invalidSqliteCharacters.hasMatch(type)) {
    throw AssertionError("Invalid characters in type name: $type");
  }
  return "objects__$type";
}
