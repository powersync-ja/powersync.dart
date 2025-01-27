import 'dart:async';
import 'dart:js_interop';

import 'package:logging/logging.dart';
import 'package:powersync_core/powersync_core.dart';
import 'package:sqlite_async/sqlite3_common.dart';
import 'package:sqlite_async/sqlite_async.dart';
import 'package:test/test.dart';
import 'package:web/web.dart' show Blob, BlobPropertyBag;
import 'abstract_test_utils.dart';

@JS('URL.createObjectURL')
external String _createObjectURL(Blob blob);

class TestUtils extends AbstractTestUtils {
  late Future<void> _isInitialized;
  late final String sqlite3WASMUri;
  late final String workerUri;

  TestUtils() {
    _isInitialized = _init();
  }

  Future<void> _init() async {
    final channel =
        spawnHybridUri('/test/server/worker_server.dart', stayAlive: true);
    final port = await channel.stream.first as int;
    sqlite3WASMUri = 'http://localhost:$port/sqlite3.wasm';
    // Cross origin workers are not supported, but we can supply a Blob
    final workerUriSource = 'http://localhost:$port/powersync_db.worker.js';

    final blob = Blob(
        <JSString>['importScripts("$workerUriSource");'.toJS].toJS,
        BlobPropertyBag(type: 'application/javascript'));
    workerUri = _createObjectURL(blob);
  }

  @override
  Future<void> cleanDb({required String path}) async {}

  @override
  Future<PowerSyncOpenFactory> testFactory(
      {String? path,
      String? sqlitePath,
      SqliteOptions options = const SqliteOptions.defaults()}) async {
    await _isInitialized;

    final webOptions = SqliteOptions(
        webSqliteOptions:
            WebSqliteOptions(wasmUri: sqlite3WASMUri, workerUri: workerUri));
    return super.testFactory(path: path, options: webOptions);
  }

  @override
  Future<PowerSyncDatabase> setupPowerSync(
      {String? path, Schema? schema, Logger? logger}) async {
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
