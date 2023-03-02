import 'dart:ffi';

import 'package:powersync/powersync.dart';
import 'package:powersync/src/bucket_storage.dart';
import 'package:powersync/src/mutex.dart';
import 'package:sqlite3/open.dart' as sqlite_open;
import 'package:sqlite3/sqlite3.dart' as sqlite;
import 'package:test/test.dart';

import 'util.dart';

DynamicLibrary _openOnLinux() {
  return DynamicLibrary.open('libsqlite3.so.0');
}

final testSetup = SqliteConnectionSetup(() async {
  sqlite_open.open.overrideFor(sqlite_open.OperatingSystem.linux, _openOnLinux);
});

const schema = Schema([
  Table('assets', [
    Column.text('created_at'),
    Column.text('make'),
    Column.text('model'),
    Column.text('serial_number'),
    Column.integer('quantity'),
    Column.text('user_id'),
    Column.text('customer_id'),
    Column.text('description')
  ]),
  Table('customers', [Column.text('name'), Column.text('email')])
]);

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

void main() {
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

    test('Basic Setup', () async {
      expect(bucketStorage.getBucketStates(), equals([]));

      bucketStorage.saveSyncData(SyncDataBatch([
        SyncBucketData(
            bucket: 'bucket1',
            data: [PUT_ASSET1_1, PUT_ASSET2_2, PUT_ASSET1_3],
            after: '0',
            nextAfter: '3')
      ]));

      expect(bucketStorage.getBucketStates(),
          equals([const BucketState(bucket: 'bucket1', opId: '3')]));

      var result = await bucketStorage.syncLocalDatabase(Checkpoint(
          lastOpId: '3',
          checksums: [
            BucketChecksum(bucket: 'bucket1', checksum: 6, count: 2)
          ]));
      expect(result, equals(SyncLocalDatabaseResult(ready: true)));

      expect(
          db.select("SELECT id, description, make FROM assets WHERE id = 'O1'"),
          equals([
            {'id': 'O1', 'description': 'bard', 'make': null}
          ]));
    });
  });
}
