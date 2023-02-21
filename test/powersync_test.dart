import 'dart:ffi';
import 'dart:io';
import 'package:sqlite3/open.dart' as sqlite_open;

import 'package:powersync/powersync.dart';
import 'package:test/test.dart';

DynamicLibrary _openOnLinux() {
  return DynamicLibrary.open('libsqlite3.so.0');
}

final testSetup = SqliteConnectionSetup(() async {
  sqlite_open.open.overrideFor(sqlite_open.OperatingSystem.linux, _openOnLinux);
});

const schema = Schema([
  Table('assets', [
    Column('created_at', 'TEXT'),
    Column('make', 'TEXT'),
    Column('model', 'TEXT'),
    Column('serial_number', 'TEXT'),
    Column('quantity', 'INTEGER'),
    Column('user_id', 'TEXT'),
    Column('customer_id', 'TEXT'),
  ]),
  Table('customers', [Column('name', 'TEXT'), Column('email', 'TEXT')])
]);

void main() {
  group('Basic Tests', () {
    setUp(() async {
      try {
        await File('test.db').delete();
      } on PathNotFoundException {
        // Not an issue
      }
    });

    test('Basic Setup', () async {
      final powerSyncDatabase = PowerSyncDatabase(
          schema: schema, path: 'test.db', sqliteSetup: testSetup);
      await powerSyncDatabase.initialize();

      var db = powerSyncDatabase.openConnection(debugName: 'db-read');
      await db.execute(
          'INSERT INTO assets(id, make) VALUES(uuid(), ?)', ['Test Make']);
      final result = await db.get('SELECT make FROM assets');
      expect(result, equals({'make': 'Test Make'}));
      expect(
          await db.get('PRAGMA journal_mode'), equals({'journal_mode': 'wal'}));
      expect(await db.get('PRAGMA locking_mode'),
          equals({'locking_mode': 'normal'}));
    });
  });
}
