@TestOn('js')
library;

import 'dart:js_interop';

import 'package:flutter_test/flutter_test.dart';
import 'package:powersync_sqlcipher/powersync.dart';
import 'package:powersync_sqlcipher/sqlite_async.dart';
import 'package:web/web.dart' as web;

void main() {
  // We can't run integration tests on the web, so this is a small smoke test
  // using the worker
  test('can use encrypted database', () async {
    final channel = spawnHybridUri('/test/worker_server.dart');
    final port = (await channel.stream.first as num).toInt();
    final sqliteWasmUri = 'http://localhost:$port/sqlite3mc.wasm';
    // Cross origin workers are not supported, but we can supply a Blob
    var sqliteUri = 'http://localhost:$port/db_worker.js';

    final blob = web.Blob(
      <web.BlobPart>['importScripts("$sqliteUri");'.toJS].toJS,
      web.BlobPropertyBag(type: 'application/javascript'),
    );
    sqliteUri = _createObjectURL(blob);

    final webOptions = SqliteOptions(
      webSqliteOptions: WebSqliteOptions(
        wasmUri: sqliteWasmUri.toString(),
        workerUri: sqliteUri,
      ),
    );

    final path = 'powersync-demo.db';

    var db = PowerSyncDatabase.withFactory(
      PowerSyncSQLCipherOpenFactory(
        path: path,
        key: 'demo-key',
        sqliteOptions: webOptions,
      ),
      schema: schema,
    );

    await db.execute('INSERT INTO users (id, name) VALUES (uuid(), ?)', [
      'My username',
    ]);
    await db.close();

    expect(() async {
      db = PowerSyncDatabase.withFactory(
        PowerSyncSQLCipherOpenFactory(
          path: path,
          key: 'changed-key',
          sqliteOptions: webOptions,
        ),
        schema: schema,
      );

      await db.initialize();
    }, throwsA(anything));
  });
}

@JS('URL.createObjectURL')
external String _createObjectURL(web.Blob blob);

final schema = Schema([
  Table('users', [Column.text('name')]),
]);
