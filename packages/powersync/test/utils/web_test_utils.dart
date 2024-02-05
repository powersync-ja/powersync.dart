import 'dart:async';
import 'dart:html';

import 'package:js/js.dart';
import 'package:powersync/powersync.dart';
import 'package:sqlite3/src/database.dart';
import 'package:sqlite_async/sqlite_async.dart';
import 'package:test/test.dart';
import 'abstract_test_utils.dart';

@JS('URL.createObjectURL')
external String _createObjectURL(Blob blob);

class TestUtils extends AbstractTestUtils {
  late Future<void> _isInitialized;
  late final String sqlite3WASMUri;
  late final String driftUri;

  TestUtils() {
    _isInitialized = _init();
  }

  Future<void> _init() async {
    final channel = spawnHybridUri('/test/server/worker_server.dart');
    final port = await channel.stream.first as int;
    sqlite3WASMUri = 'http://localhost:$port/sqlite3.wasm';
    // Cross origin workers are not supported, but we can supply a Blob
    driftUri = 'http://localhost:$port/drift_worker.js';
  }

  @override
  Future<void> cleanDb({required String path}) async {}

  @override
  Future<PowerSyncOpenFactory> testFactory(
      {String? path,
      String? sqlitePath,
      SqliteOptions options = const SqliteOptions.defaults()}) async {
    await _isInitialized;
    final blob =
        Blob(<String>['importScripts("$driftUri");'], 'application/javascript');
    final sqliteDriftUri = _createObjectURL(blob);

    final webOptions = SqliteOptions(
        webSqliteOptions: WebSqliteOptions(
            wasmUri: sqlite3WASMUri, workerUri: sqliteDriftUri));
    return super.testFactory(path: path, options: webOptions);
  }

  @override
  Future<PowerSyncDatabase> setupPowerSync(
      {String? path, Schema? schema}) async {
    await _isInitialized;
    return super.setupPowerSync(path: path, schema: schema);
  }

  @override
  Future<CommonDatabase> setupSqlite(
      {required PowerSyncDatabase powersync}) async {
    await _isInitialized;
    return super.setupSqlite(powersync: powersync);
  }
}
