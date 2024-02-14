import 'dart:convert';

import 'package:powersync/sqlite3_common.dart';
import 'package:powersync/src/log_internal.dart';
import 'package:powersync/src/sync_types.dart';
import 'package:sqlite_async/sqlite3.dart' as sqlite;

import 'package:powersync/src/bucket_storage.dart';

/// Native implementation for [BucketStorage]
/// Uses direct SQLite3 connection for memory and performance
/// optimizations.
class NativeBucketStorage extends BucketStorage {
  NativeBucketStorage(super.db);

  @override

  /// Native specific version for updating objects from buckets
  /// this uses the SQLite3 database directly for better memory usage.
  Future<bool> updateObjectsFromBuckets(Checkpoint checkpoint) async {
    // Internal connection is private, but can be accessed via a transaction
    return writeTransaction((tx) {
      return tx.computeWithDatabase((db) async {
        if (!(await canUpdateLocal(tx))) {
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
        var stmt = db.prepare(
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
        try {
          // TODO: Perhaps we don't need batching for this?
          var cursor = stmt.selectCursor([]);
          List<sqlite.Row> rows = [];
          while (cursor.moveNext()) {
            var row = cursor.current;
            rows.add(row);

            if (rows.length >= 10000) {
              _saveOps(db, rows);
              rows = [];
            }
          }
          if (rows.isNotEmpty) {
            _saveOps(db, rows);
          }
        } finally {
          stmt.dispose();
        }

        db.execute("""UPDATE ps_buckets
                SET last_applied_op = last_op
                WHERE last_applied_op != last_op""");

        isolateLogger.fine('Applied checkpoint ${checkpoint.lastOpId}');
        return true;
      });
    });
  }

  /// Native specific version of saveOps which operates directly
  /// on the SQLite3 connection
  /// { type: string; id: string; data: string; buckets: string; op_id: string }[]
  void _saveOps(CommonDatabase db, List<sqlite.Row> rows) {
    Map<String, List<sqlite.Row>> byType = {};
    for (final row in rows) {
      byType.putIfAbsent(row['type'], () => []).add(row);
    }

    for (final entry in byType.entries) {
      final type = entry.key;
      final typeRows = entry.value;
      final table = getTypeTableName(type);

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
        db.execute(r"""REPLACE INTO ps_untyped(type, id, data)
        SELECT ?,
      json_extract(json_each.value, '$.id'),
      json_extract(json_each.value, '$.data')
    FROM json_each(?)""", [type, jsonEncode(puts)]);

        db.execute("""DELETE FROM ps_untyped
    WHERE type = ?
    AND id IN (SELECT json_each.value FROM json_each(?))""",
            [type, jsonEncode(removeIds.toList())]);
      }
    }
  }
}
