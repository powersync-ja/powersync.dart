import 'dart:async';
import 'dart:convert';

import 'package:collection/collection.dart';
import 'package:sqlite_async/mutex.dart';
import 'package:sqlite_async/sqlite3.dart' as sqlite;
import 'package:sqlite_async/sqlite3_common.dart';

import 'crud.dart';
import 'database_utils.dart';
import 'schema_logic.dart';
import 'sync_types.dart';

const compactOperationInterval = 1000;

class BucketStorage {
  final CommonDatabase _internalDb;
  final Mutex mutex;
  bool _hasCompletedSync = false;
  bool _pendingBucketDeletes = false;
  int _compactCounter = compactOperationInterval;

  BucketStorage(CommonDatabase db, {required this.mutex}) : _internalDb = db {
    _init();
  }

  _init() {}

  // Use only for read statements
  sqlite.ResultSet select(String query, [List<Object?> parameters = const []]) {
    return _internalDb.select(query, parameters);
  }

  void startSession() {}

  List<BucketState> getBucketStates() {
    final rows = select(
        'SELECT name as bucket, cast(last_op as TEXT) as op_id FROM ps_buckets WHERE pending_delete = 0');
    return [
      for (var row in rows)
        BucketState(bucket: row['bucket'], opId: row['op_id'])
    ];
  }

  Future<void> streamOp(String op) async {
    await writeTransaction((db) {
      db.execute('INSERT INTO powersync_operations(op, data) VALUES(?, ?)',
          ['stream', op]);
    });
  }

  Future<void> saveSyncData(SyncDataBatch batch) async {
    var count = 0;

    await writeTransaction((db) {
      for (var b in batch.buckets) {
        count += b.data.length;
        _updateBucket2(
            db,
            jsonEncode({
              'buckets': [b]
            }));
      }
    });
    _compactCounter += count;
  }

  void _updateBucket2(CommonDatabase db, String json) {
    db.execute('INSERT INTO powersync_operations(op, data) VALUES(?, ?)',
        ['save', json]);
  }

  Future<void> removeBuckets(List<String> buckets) async {
    for (final bucket in buckets) {
      await deleteBucket(bucket);
    }
  }

  Future<void> deleteBucket(String bucket) async {
    await writeTransaction((db) {
      db.execute('INSERT INTO powersync_operations(op, data) VALUES(?, ?)',
          ['delete_bucket', bucket]);
    });

    _pendingBucketDeletes = true;
  }

  bool hasCompletedSync() {
    if (_hasCompletedSync) {
      return true;
    }
    final rs = select(
        "SELECT name, last_applied_op FROM ps_buckets WHERE last_applied_op > 0 LIMIT 1");
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
    final bucketNames = [for (final c in checkpoint.checksums) c.bucket];

    await writeTransaction((db) {
      db.execute(
          "UPDATE ps_buckets SET last_op = ? WHERE name IN (SELECT json_each.value FROM json_each(?))",
          [checkpoint.lastOpId, jsonEncode(bucketNames)]);
      if (checkpoint.writeCheckpoint != null) {
        db.execute("UPDATE ps_buckets SET last_op = ? WHERE name = '\$local'",
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
    return writeTransaction((db) {
      db.execute("INSERT INTO powersync_operations(op, data) VALUES(?, ?)",
          ['sync_local', '']);
      final rs = db.select('SELECT last_insert_rowid() as result');
      final result = rs[0]['result'];
      if (result == 1) {
        return true;
      } else {
        // can_update_local(db) == false
        return false;
      }
    });
  }

  SyncLocalDatabaseResult validateChecksums(Checkpoint checkpoint) {
    final rs = select("SELECT powersync_validate_checkpoint(?) as result",
        [jsonEncode(checkpoint)]);
    final result = jsonDecode(rs[0]['result']);
    if (result['valid']) {
      return SyncLocalDatabaseResult(ready: true);
    } else {
      return SyncLocalDatabaseResult(
          checkpointValid: false,
          ready: false,
          checkpointFailures: result['failed_buckets'].cast<String>());
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
      await writeTransaction((db) {
        db.select('PRAGMA wal_checkpoint(TRUNCATE)');
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
      await writeTransaction((db) {
        db.execute('INSERT INTO powersync_operations(op, data) VALUES (?, ?)',
            ['delete_pending_buckets', '']);
      });
      _pendingBucketDeletes = false;
    }
  }

  Future<void> _clearRemoveOps() async {
    if (_compactCounter < compactOperationInterval) {
      return;
    }

    await writeTransaction((db) {
      db.execute('INSERT INTO powersync_operations(op, data) VALUES (?, ?)',
          ['clear_remove_ops', '']);
    });
    _compactCounter = 0;
  }

  void setTargetCheckpoint(Checkpoint checkpoint) {
    // No-op for now
  }

  Future<bool> updateLocalTarget(
      Future<String> Function() checkpointCallback) async {
    final rs1 = select(
        'SELECT target_op FROM ps_buckets WHERE name = \'\$local\' AND target_op = $maxOpId');
    if (rs1.isEmpty) {
      // Nothing to update
      return false;
    }
    final rs =
        select('SELECT seq FROM sqlite_sequence WHERE name = \'ps_crud\'');
    if (rs.isEmpty) {
      // Nothing to update
      return false;
    }
    int seqBefore = rs.first['seq'];
    var opId = await checkpointCallback();

    return await writeTransaction((tx) {
      final anyData = tx.select('SELECT 1 FROM ps_crud LIMIT 1');
      if (anyData.isNotEmpty) {
        return false;
      }
      final rs =
          tx.select('SELECT seq FROM sqlite_sequence WHERE name = \'ps_crud\'');
      assert(rs.isNotEmpty);

      int seqAfter = rs.first['seq'];
      if (seqAfter != seqBefore) {
        // New crud data may have been uploaded since we got the checkpoint. Abort.
        return false;
      }

      tx.select(
          "UPDATE ps_buckets SET target_op = ? WHERE name='\$local'", [opId]);

      return true;
    });
  }

  bool hasCrud() {
    final anyData = select('SELECT 1 FROM ps_crud LIMIT 1');
    return anyData.isNotEmpty;
  }

  /// For tests only. Others should use the version on PowerSyncDatabase.
  CrudBatch? getCrudBatch({int limit = 100}) {
    if (!hasCrud()) {
      return null;
    }

    final rows =
        select('SELECT * FROM ps_crud ORDER BY id ASC LIMIT ?', [limit]);
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
          await writeTransaction((db) {
            db.execute('DELETE FROM ps_crud WHERE id <= ?', [last.clientId]);
            if (writeCheckpoint != null &&
                db.select('SELECT 1 FROM ps_crud LIMIT 1').isEmpty) {
              db.execute(
                  'UPDATE ps_buckets SET target_op = $writeCheckpoint WHERE name=\'\$local\'');
            } else {
              db.execute(
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
      FutureOr<T> Function(CommonDatabase tx) callback,
      {Duration? lockTimeout}) async {
    return mutex.lock(() async {
      final r = await asyncDirectTransaction(_internalDb, callback);
      return r;
    });
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

  Map<String, dynamic> toJson() {
    return {
      'bucket': bucket,
      'has_more': hasMore,
      'after': after,
      'next_after': nextAfter,
      'data': data
    };
  }
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

  Map<String, dynamic> toJson() {
    return {
      'op_id': opId,
      'op': op?.toJson(),
      'object_type': rowType,
      'object_id': rowId,
      'checksum': checksum,
      'subkey': subkey,
      'data': data
    };
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

  String toJson() {
    switch (this) {
      case clear:
        return 'CLEAR';
      case move:
        return 'MOVE';
      case put:
        return 'PUT';
      case remove:
        return 'REMOVE';
      default:
        return '';
    }
  }
}
