import 'dart:io';
import 'package:powersync/powersync.dart';

late PowerSyncDatabase db;

const schema = Schema([
  Table.localOnly('data', [Column.text('contents')])
]);

final parameterSets = List.generate(1000, (i) => [uuid.v4(), 'Row $i']);

openDatabase() async {
  db = PowerSyncDatabase(schema: schema, path: 'test.db');
  await db.initialize();
}

singleWrites() async {
  // Execute each write as a separate statement.
  // Each write flushes the changes to persistent storage, so this is slow.
  for (var params in parameterSets) {
    await db.execute('INSERT INTO data(id, contents) VALUES(?, ?)', params);
  }
}

transactionalWrites() async {
  // Combine all the writes into a single transaction, only flushing to
  // persistent storage once.
  await db.writeTransaction((tx) async {
    for (var params in parameterSets) {
      await tx.execute('INSERT INTO data(id, contents) VALUES(?, ?)', params);
    }
  });
}

batchWrites() async {
  // Combine all the writes into a single batch, automatically wrapped in a transaction.
  // This avoids the overhead of asynchronously waiting for each call to complete,
  // and also only parses the SQL statement once.
  await db.executeBatch(
      'INSERT INTO data(id, contents) VALUES(?, ?)', parameterSets);
}

inIsolateWrites() async {
  // This is the same as executeBatch, but using the low-level sqlite APIs.
  // The call is executed in a transaction in the database isolate, with
  // synchronous access to the database.
  // Use this for more control over the database calls.

  var closureParameterSets = parameterSets;

  await db.computeWithDatabase((db) async {
    var statement = db.prepare('INSERT INTO data(id, contents) VALUES(?, ?)');
    try {
      for (var params in closureParameterSets) {
        statement.execute(params);
      }
    } finally {
      statement.dispose();
    }
  });
}

main() async {
  await openDatabase();
  for (var call in [
    singleWrites,
    transactionalWrites,
    batchWrites,
    inIsolateWrites
  ]) {
    await db.execute('DELETE FROM data WHERE 1');
    var watch = Stopwatch()..start();
    await call();
    var duration = watch.elapsedMilliseconds;
    print('${getFunctionName(call)} completed in ${duration}ms');
  }
  db.disconnect();
  exit(0);
}

String? getFunctionName(Function fn) {
  return RegExp(r"'(\w+)'").firstMatch(fn.toString())?.group(1);
}
