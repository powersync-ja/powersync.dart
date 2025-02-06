import 'dart:io';

import 'package:powersync/powersync.dart';

late PowerSyncDatabase db;

const schema = Schema([
  Table.localOnly('data', [Column.text('contents')])
]);

final parameterSets = List.generate(1000, (i) => [uuid.v4(), 'Row $i']);

Future<void> openDatabase() async {
  db = PowerSyncDatabase(schema: schema, path: 'test.db');
  await db.initialize();
}

Future<void> main() async {
  await openDatabase();

  // Watch a single query.
  // The query is executed every time one of its source tables are changed.
  var subscription1 =
      db.watch('SELECT count() AS count FROM data').listen((results) {
    print('Results: $results');
  }, onError: (Object e) {
    print('Query failed: $e');
  });

  // Watch for changes to one or more tables.
  // For this form, the tables to watch must be manually specified.
  // Use asyncMap here to avoid the event being triggered while previous queries
  // are still running.
  var subscription2 = db.onChange(['data']).asyncMap((update) async {
    var count = await db.get('SELECT count() AS count FROM data');
    var length =
        await db.get('SELECT sum(length(contents)) AS length FROM data');
    print(
        'Results after change to ${update.tables}: ${count['count']} entries, ${length['length']} characters');
  }).listen((_) {}, onError: (Object e) {
    print('Query failed: $e');
  });

  for (var i = 0; i < 10; i++) {
    await db.execute(
        'INSERT INTO data(id, contents) VALUES(uuid(), ?)', ['Row $i']);
    await Future<void>.delayed(Duration(milliseconds: 500));
  }

  subscription1.cancel();
  subscription2.cancel();
  db.disconnect();
  exit(0);
}
