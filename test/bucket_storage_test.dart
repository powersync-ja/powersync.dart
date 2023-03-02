import 'package:powersync/powersync.dart';
import 'package:powersync/src/bucket_storage.dart';
import 'package:powersync/src/mutex.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;
import 'package:test/test.dart';

import 'util.dart';

const PUT_ASSET1_1 = OplogEntry(
    opId: '1',
    op: OpType.put,
    objectType: 'assets',
    objectId: 'O1',
    data: {'description': 'bar'},
    checksum: 1);

const PUT_ASSET2_2 = OplogEntry(
    opId: '2',
    op: OpType.put,
    objectType: 'assets',
    objectId: 'O2',
    data: {'description': 'bar'},
    checksum: 2);

const PUT_ASSET1_3 = OplogEntry(
    opId: '3',
    op: OpType.put,
    objectType: 'assets',
    objectId: 'O1',
    data: {'description': 'bard'},
    checksum: 3);

const REMOVE_ASSET1_4 = OplogEntry(
    opId: '4',
    op: OpType.remove,
    objectType: 'assets',
    objectId: 'O1',
    checksum: 4);

const REMOVE_ASSET1_5 = OplogEntry(
    opId: '5',
    op: OpType.remove,
    objectType: 'assets',
    objectId: 'O1',
    checksum: 5);

void main() {
  setupLogger();

  group('Bucket Storage Tests', () {
    late PowerSyncDatabase powersync;
    late sqlite.Database db;
    late BucketStorage bucketStorage;
    late String path;

    setUp(() async {
      path = dbPath();
      await cleanDb(path: path);

      powersync = await setupPowerSync(path: path);
      db = await setupSqlite(powersync: powersync);
      bucketStorage = BucketStorage(db, mutex: Mutex());
    });

    Future<void> syncLocalChecked(Checkpoint checkpoint) async {
      var result = await bucketStorage.syncLocalDatabase(checkpoint);
      expect(result, equals(SyncLocalDatabaseResult(ready: true)));
    }

    void expectAsset1_3() {
      expect(
          db.select("SELECT id, description, make FROM assets WHERE id = 'O1'"),
          equals([
            {'id': 'O1', 'description': 'bard', 'make': null}
          ]));
    }

    void expectNoAsset1() {
      expect(
          db.select("SELECT id, description, make FROM assets WHERE id = 'O1'"),
          equals([]));
    }

    void expectNoAssets() {
      expect(db.select("SELECT id, description, make FROM assets"), equals([]));
    }

    test('Basic Setup', () async {
      expect(bucketStorage.getBucketStates(), equals([]));

      await bucketStorage.saveSyncData(SyncDataBatch([
        SyncBucketData(
          bucket: 'bucket1',
          data: [PUT_ASSET1_1, PUT_ASSET2_2, PUT_ASSET1_3],
        )
      ]));

      expect(bucketStorage.getBucketStates(),
          equals([const BucketState(bucket: 'bucket1', opId: '3')]));

      await syncLocalChecked(Checkpoint(
          lastOpId: '3',
          checksums: [BucketChecksum(bucket: 'bucket1', checksum: 6)]));

      expectAsset1_3();
    });

    test('should get an object from multiple buckets', () async {
      await bucketStorage.saveSyncData(SyncDataBatch([
        SyncBucketData(
          bucket: 'bucket1',
          data: [PUT_ASSET1_3],
        ),
        SyncBucketData(bucket: 'bucket2', data: [PUT_ASSET1_3])
      ]));

      await syncLocalChecked(Checkpoint(lastOpId: '3', checksums: [
        BucketChecksum(bucket: 'bucket1', checksum: 3),
        BucketChecksum(bucket: 'bucket2', checksum: 3)
      ]));

      expectAsset1_3();
    });

    test('should prioritize later updates', () async {
      // Test behaviour when the same object is present in multiple buckets.
      // In this case, there are two different versions in the different buckets.
      // While we should not get this with our server implementation, the client still specifies this behaviour:
      // The largest op_id wins.
      await bucketStorage.saveSyncData(SyncDataBatch([
        SyncBucketData(bucket: 'bucket1', data: [PUT_ASSET1_3]),
        SyncBucketData(bucket: 'bucket2', data: [PUT_ASSET1_1])
      ]));

      await syncLocalChecked(Checkpoint(lastOpId: '3', checksums: [
        BucketChecksum(bucket: 'bucket1', checksum: 3),
        BucketChecksum(bucket: 'bucket2', checksum: 1)
      ]));

      expectAsset1_3();
    });

    test('should ignore a remove from one bucket', () async {
      // When we have 1 PUT and 1 REMOVE, the object must be kept.
      await bucketStorage.saveSyncData(SyncDataBatch([
        SyncBucketData(bucket: 'bucket1', data: [PUT_ASSET1_3]),
        SyncBucketData(bucket: 'bucket2', data: [PUT_ASSET1_3, REMOVE_ASSET1_4])
      ]));

      await syncLocalChecked(Checkpoint(lastOpId: '4', checksums: [
        BucketChecksum(bucket: 'bucket1', checksum: 3),
        BucketChecksum(bucket: 'bucket2', checksum: 7)
      ]));

      expectAsset1_3();
    });

    test('should remove when removed from all buckets', () async {
      // When we only have REMOVE left for an object, it must be deleted.
      await bucketStorage.saveSyncData(SyncDataBatch([
        SyncBucketData(
            bucket: 'bucket1', data: [PUT_ASSET1_3, REMOVE_ASSET1_5]),
        SyncBucketData(bucket: 'bucket2', data: [PUT_ASSET1_3, REMOVE_ASSET1_4])
      ]));

      await syncLocalChecked(Checkpoint(lastOpId: '5', checksums: [
        BucketChecksum(bucket: 'bucket1', checksum: 8),
        BucketChecksum(bucket: 'bucket2', checksum: 7)
      ]));

      expectNoAssets();
    });

    test('should fail checksum validation', () async {
      // Simple checksum validation
      await bucketStorage.saveSyncData(SyncDataBatch([
        SyncBucketData(
            bucket: 'bucket1',
            data: [PUT_ASSET1_1, PUT_ASSET2_2, PUT_ASSET1_3]),
      ]));

      var result = await bucketStorage
          .syncLocalDatabase(Checkpoint(lastOpId: '3', checksums: [
        BucketChecksum(bucket: 'bucket1', checksum: 10),
        BucketChecksum(bucket: 'bucket2', checksum: 1)
      ]));
      expect(
          result,
          equals(SyncLocalDatabaseResult(
              ready: false,
              checkpointValid: false,
              checkpointFailures: ['bucket1', 'bucket2'])));

      expectNoAssets();
    });

    test('should delete buckets', () async {
      await bucketStorage.saveSyncData(SyncDataBatch([
        SyncBucketData(
          bucket: 'bucket1',
          data: [PUT_ASSET1_3],
        ),
        SyncBucketData(
          bucket: 'bucket2',
          data: [PUT_ASSET1_3],
        ),
      ]));

      await bucketStorage.removeBuckets(['bucket2']);
      // The delete only takes effect after syncLocal.

      await syncLocalChecked(Checkpoint(lastOpId: '3', checksums: [
        BucketChecksum(bucket: 'bucket1', checksum: 3),
      ]));

      // Bucket is deleted, but object is still present in other buckets.
      expectAsset1_3();

      await bucketStorage.removeBuckets(['bucket1']);
      await syncLocalChecked(Checkpoint(lastOpId: '3', checksums: []));
      // Both buckets deleted - object removed.
      expectNoAssets();
    });

    test('should delete and re-create buckets', () async {
      // Save some data
      await bucketStorage.saveSyncData(SyncDataBatch([
        SyncBucketData(
          bucket: 'bucket1',
          data: [PUT_ASSET1_1],
        ),
      ]));

      // Delete the bucket
      await bucketStorage.removeBuckets(['bucket1']);

      // Save some data again
      await bucketStorage.saveSyncData(SyncDataBatch([
        SyncBucketData(
          bucket: 'bucket1',
          data: [PUT_ASSET1_1, PUT_ASSET1_3],
        ),
      ]));
      // Delete again
      await bucketStorage.removeBuckets(['bucket1']);

      // Final save of data
      await bucketStorage.saveSyncData(SyncDataBatch([
        SyncBucketData(
          bucket: 'bucket1',
          data: [PUT_ASSET1_1, PUT_ASSET1_3],
        ),
      ]));

      // Check that the data is there
      await syncLocalChecked(Checkpoint(lastOpId: '3', checksums: [
        BucketChecksum(bucket: 'bucket1', checksum: 4),
      ]));
      expectAsset1_3();

      // Now final delete
      await bucketStorage.removeBuckets(['bucket1']);
      await syncLocalChecked(Checkpoint(lastOpId: '3', checksums: []));
      expectNoAssets();
    });

    test('should handle MOVE', () async {
      await bucketStorage.saveSyncData(SyncDataBatch([
        SyncBucketData(
          bucket: 'bucket1',
          data: [
            OplogEntry(
                opId: '1', op: OpType.move, checksum: 1, data: {'target': '3'})
          ],
        ),
      ]));

      // At this point, we have target: 3, but don't have that op yet, so we cannot sync.
      final result = await bucketStorage.syncLocalDatabase(Checkpoint(
          lastOpId: '2',
          checksums: [BucketChecksum(bucket: 'bucket1', checksum: 1)]));
      // Checksum passes, but we don't have a complete checkpoint
      expect(result, equals(SyncLocalDatabaseResult(ready: false)));

      await bucketStorage.saveSyncData(SyncDataBatch([
        SyncBucketData(
          bucket: 'bucket1',
          data: [PUT_ASSET1_3],
        ),
      ]));

      await syncLocalChecked(Checkpoint(
          lastOpId: '3',
          checksums: [BucketChecksum(bucket: 'bucket1', checksum: 4)]));

      expectAsset1_3();
    });

    test('should handle CLEAR', () async {
      // Save some data
      await bucketStorage.saveSyncData(SyncDataBatch([
        SyncBucketData(
          bucket: 'bucket1',
          data: [PUT_ASSET1_1],
        ),
      ]));

      await syncLocalChecked(Checkpoint(
          lastOpId: '1',
          checksums: [BucketChecksum(bucket: 'bucket1', checksum: 1)]));

      // CLEAR, then save new data
      await bucketStorage.saveSyncData(SyncDataBatch([
        SyncBucketData(
          bucket: 'bucket1',
          data: [
            OplogEntry(opId: '2', op: OpType.clear, checksum: 2),
            OplogEntry(
                opId: '3',
                checksum: 3,
                op: PUT_ASSET2_2.op,
                data: PUT_ASSET2_2.data,
                objectId: PUT_ASSET2_2.objectId,
                objectType: PUT_ASSET2_2.objectType)
          ],
        ),
      ]));

      await syncLocalChecked(Checkpoint(
          lastOpId: '3',
          // 2 + 3. 1 is replaced with 2.
          checksums: [BucketChecksum(bucket: 'bucket1', checksum: 5)]));

      expectNoAsset1();
      expect(
          db.select("SELECT id, description FROM assets WHERE id = 'O2'"),
          equals([
            {'id': 'O2', 'description': 'bar'}
          ]));
    });

    test('update with new types', () async {
      // Test case where a type is added to the schema after we already have the data.

      // Re-initialize with empty database
      await cleanDb(path: path);

      powersync = PowerSyncDatabase(
          schema: const Schema([]), path: path, sqliteSetup: testSetup);
      await powersync.initialize();
      db = await setupSqlite(powersync: powersync);
      bucketStorage = BucketStorage(db, mutex: Mutex());

      await bucketStorage.saveSyncData(SyncDataBatch([
        SyncBucketData(
          bucket: 'bucket1',
          data: [PUT_ASSET1_1, PUT_ASSET2_2, PUT_ASSET1_3],
        ),
      ]));

      await syncLocalChecked(Checkpoint(
          lastOpId: '4',
          checksums: [BucketChecksum(bucket: 'bucket1', checksum: 6)]));
      expect(
          () => db.select('SELECT * FROM assets'),
          throwsA((e) =>
              e is sqlite.SqliteException &&
              e.message.contains('no such table')));

      // Now open another instance with new schema
      // TODO: close existing database when we have an API for that
      powersync =
          PowerSyncDatabase(schema: schema, path: path, sqliteSetup: testSetup);
      db = await setupSqlite(powersync: powersync);

      expectAsset1_3();
    });

    test('should remove types', () async {
      await bucketStorage.saveSyncData(SyncDataBatch([
        SyncBucketData(
          bucket: 'bucket1',
          data: [PUT_ASSET1_1, PUT_ASSET2_2, PUT_ASSET1_3],
        ),
      ]));

      await syncLocalChecked(Checkpoint(
          lastOpId: '3',
          checksums: [BucketChecksum(bucket: 'bucket1', checksum: 6)]));

      expectAsset1_3();

      // Now open another instance with new schema
      // TODO: close existing database when we have an API for that
      powersync = PowerSyncDatabase(
          schema: const Schema([]), path: path, sqliteSetup: testSetup);
      db = await setupSqlite(powersync: powersync);
      expect(
          () => db.select('SELECT * FROM assets'),
          throwsA((e) =>
              e is sqlite.SqliteException &&
              e.message.contains('no such table')));

      // Add schema again
      powersync =
          PowerSyncDatabase(schema: schema, path: path, sqliteSetup: testSetup);
      db = await setupSqlite(powersync: powersync);

      expectAsset1_3();
    });

    test('should compact', () async {
      // Test compacting behaviour.
      // This test relies heavily on internals, and will have to be updated when the compact implementation is updated.

      await bucketStorage.saveSyncData(SyncDataBatch([
        SyncBucketData(
            bucket: 'bucket1',
            data: [PUT_ASSET1_1, PUT_ASSET2_2, REMOVE_ASSET1_4])
      ]));

      await syncLocalChecked(Checkpoint(
          lastOpId: '4',
          checksums: [BucketChecksum(bucket: 'bucket1', checksum: 7)]));

      await bucketStorage.forceCompact();

      await syncLocalChecked(Checkpoint(
          lastOpId: '4',
          checksums: [BucketChecksum(bucket: 'bucket1', checksum: 7)]));

      final stats = db.select(
          'SELECT object_type as type, object_id as id, count(*) as count FROM oplog GROUP BY object_type, object_id ORDER BY object_type, object_id');
      expect(
          stats,
          equals([
            {'type': 'assets', 'id': 'O2', 'count': 1}
          ]));
    });

    test('should not sync local db with pending crud - server removed',
        () async {
      await bucketStorage.saveSyncData(SyncDataBatch([
        SyncBucketData(
          bucket: 'bucket1',
          data: [PUT_ASSET1_1, PUT_ASSET2_2, PUT_ASSET1_3],
        ),
      ]));

      await syncLocalChecked(Checkpoint(
          lastOpId: '3',
          checksums: [BucketChecksum(bucket: 'bucket1', checksum: 6)]));

      // Local save
      db.execute('INSERT INTO assets(id) VALUES(?)', ['O3']);
      expect(
          db.select('SELECT id FROM assets WHERE id = \'O3\''),
          equals([
            {'id': 'O3'}
          ]));

      // At this point, we have data in the crud table, and are not able to sync the local db.
      final result = await bucketStorage.syncLocalDatabase(Checkpoint(
          lastOpId: '3',
          checksums: [BucketChecksum(bucket: 'bucket1', checksum: 6)]));
      expect(result, equals(SyncLocalDatabaseResult(ready: false)));

      final batch = bucketStorage.getCrudBatch();
      await batch!.complete();
      await bucketStorage.updateLocalTarget(() async {
        return '4';
      });

      // At this point, the data has been uploaded, but not synced back yet.
      final result3 = await bucketStorage.syncLocalDatabase(Checkpoint(
          lastOpId: '3',
          checksums: [BucketChecksum(bucket: 'bucket1', checksum: 6)]));
      expect(result3, equals(SyncLocalDatabaseResult(ready: false)));

      // The data must still be present locally.
      expect(
          db.select('SELECT id FROM assets WHERE id = \'O3\''),
          equals([
            {'id': 'O3'}
          ]));

      await bucketStorage.saveSyncData(
          SyncDataBatch([SyncBucketData(bucket: 'bucket1', data: [])]));

      // No we have synced the data back (or lack of data in this case),
      // so we can do a local sync.
      await syncLocalChecked(Checkpoint(
          lastOpId: '5',
          checksums: [BucketChecksum(bucket: 'bucket1', checksum: 6)]));

      // Since the object was not in the sync response, it is deleted.
      expect(db.select('SELECT id FROM assets WHERE id = \'O3\''), equals([]));
    });

    test(
        'should not sync local db with pending crud when more crud is added (1)',
        () async {
      await bucketStorage.saveSyncData(SyncDataBatch([
        SyncBucketData(
          bucket: 'bucket1',
          data: [PUT_ASSET1_1, PUT_ASSET2_2, PUT_ASSET1_3],
        ),
      ]));

      await syncLocalChecked(Checkpoint(
          lastOpId: '3',
          checksums: [BucketChecksum(bucket: 'bucket1', checksum: 6)]));

      // Local save
      db.execute('INSERT INTO assets(id) VALUES(?)', ['O3']);

      final batch = bucketStorage.getCrudBatch();
      await batch!.complete();
      await bucketStorage.updateLocalTarget(() async {
        return '4';
      });

      final result3 = await bucketStorage.syncLocalDatabase(Checkpoint(
          lastOpId: '3',
          checksums: [BucketChecksum(bucket: 'bucket1', checksum: 6)]));
      expect(result3, equals(SyncLocalDatabaseResult(ready: false)));

      await bucketStorage.saveSyncData(
          SyncDataBatch([SyncBucketData(bucket: 'bucket1', data: [])]));

      // Add more data before syncLocalDatabase.
      db.execute('INSERT INTO assets(id) VALUES(?)', ['O4']);

      final result4 = await bucketStorage.syncLocalDatabase(Checkpoint(
          lastOpId: '5',
          checksums: [BucketChecksum(bucket: 'bucket1', checksum: 6)]));
      expect(result4, equals(SyncLocalDatabaseResult(ready: false)));
    });

    test(
        'should not sync local db with pending crud when more crud is added (2)',
        () async {
      await bucketStorage.saveSyncData(SyncDataBatch([
        SyncBucketData(
          bucket: 'bucket1',
          data: [PUT_ASSET1_1, PUT_ASSET2_2, PUT_ASSET1_3],
        ),
      ]));

      await syncLocalChecked(Checkpoint(
          lastOpId: '3',
          checksums: [BucketChecksum(bucket: 'bucket1', checksum: 6)]));

      // Local save
      db.execute('INSERT INTO assets(id) VALUES(?)', ['O3']);
      final batch = bucketStorage.getCrudBatch();
      // Add more data before the complete() call

      db.execute('INSERT INTO assets(id) VALUES(?)', ['O4']);
      await batch!.complete();
      await bucketStorage.updateLocalTarget(() async {
        return '4';
      });

      await bucketStorage.saveSyncData(SyncDataBatch([
        SyncBucketData(
          bucket: 'bucket1',
          data: [],
        ),
      ]));

      final result4 = await bucketStorage.syncLocalDatabase(Checkpoint(
          lastOpId: '5',
          checksums: [BucketChecksum(bucket: 'bucket1', checksum: 6)]));
      expect(result4, equals(SyncLocalDatabaseResult(ready: false)));
    });

    test('should not sync local db with pending crud - update on server',
        () async {
      await bucketStorage.saveSyncData(SyncDataBatch([
        SyncBucketData(
          bucket: 'bucket1',
          data: [PUT_ASSET1_1, PUT_ASSET2_2, PUT_ASSET1_3],
        ),
      ]));

      await syncLocalChecked(Checkpoint(
          lastOpId: '3',
          checksums: [BucketChecksum(bucket: 'bucket1', checksum: 6)]));

      // Local save
      db.execute('INSERT INTO assets(id) VALUES(?)', ['O3']);
      final batch = bucketStorage.getCrudBatch();
      await batch!.complete();
      await bucketStorage.updateLocalTarget(() async {
        return '4';
      });

      await bucketStorage.saveSyncData(SyncDataBatch([
        SyncBucketData(
          bucket: 'bucket1',
          data: [
            OplogEntry(
                opId: '5',
                op: OpType.put,
                objectType: 'assets',
                objectId: 'O3',
                checksum: 5,
                data: {'description': 'server updated'})
          ],
        ),
      ]));

      await syncLocalChecked(Checkpoint(
          lastOpId: '5',
          checksums: [BucketChecksum(bucket: 'bucket1', checksum: 11)]));

      expect(
          db.select('SELECT description FROM assets WHERE id = \'O3\''),
          equals([
            {'description': 'server updated'}
          ]));
    });
  });
}
