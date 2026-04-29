import 'dart:io';

import 'package:powersync/powersync.dart';
import 'package:path/path.dart' as p;

/// An app using a PowerSync database.
///
/// We use this to test the VM service extension making this database available
/// through an IPC protocol.
void main(List<String> args) async {
  String databasePath;
  if (args.isEmpty) {
    final dir = await Directory.systemTemp.createTemp('ps-dart-extension-test');
    databasePath = p.join(dir.path, 'test.db');
  } else {
    databasePath = args[0];
  }

  const schema = Schema([
    Table('users', [Column.text('name')])
  ]);
  final database = PowerSyncDatabase(schema: schema, path: databasePath);
  await database.initialize();
  print('database is running at $databasePath!');
}
