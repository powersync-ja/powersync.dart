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
    Column.text('created_at'),
    Column.text('make'),
    Column.text('model'),
    Column.text('serial_number'),
    Column.integer('quantity'),
    Column.text('user_id'),
    Column.text('customer_id'),
  ]),
  Table('customers', [Column.text('name'), Column.text('email')])
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
      final db = PowerSyncDatabase(
          schema: schema, path: 'test.db', sqliteSetup: testSetup);
      await db.initialize();
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
