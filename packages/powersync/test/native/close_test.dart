@TestOn('!browser')
library;

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:powersync/powersync.dart';
import 'package:test/test.dart';

const schema = Schema([
  Table('items', [Column.text('description')]),
]);

void main() {
  test('close releases the native database file handle', () async {
    final directory = await Directory.systemTemp.createTemp(
      'powersync_database_close_test',
    );

    final database = PowerSyncDatabase(
      schema: schema,
      path: p.join(directory.path, 'powersync-test.db'),
    );

    await database.initialize();
    await database.close();

    await directory.delete(recursive: true);
    expect(await directory.exists(), isFalse);
  });
}
