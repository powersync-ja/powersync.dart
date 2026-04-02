import 'dart:async';
import 'dart:js_interop';

import 'package:powersync/powersync.dart';
import 'package:powersync/web.dart';
import 'package:sqlite3/wasm.dart';
import 'package:sqlite_async/sqlite_async.dart';
import 'package:test/test.dart';
import 'package:web/web.dart' show Blob, BlobPropertyBag;
import 'abstract_test_utils.dart';

@JS('URL.createObjectURL')
external String _createObjectURL(Blob blob);

class TestUtils extends AbstractTestUtils {
  late Future<void> _isInitialized;
  late final String sqlite3WASMUri;
  late final String sqlite3McUri;
  late final String workerUri;

  TestUtils() {
    _isInitialized = _init();
  }

  Future<void> _init() async {
    final channel =
        spawnHybridUri('/test/server/worker_server.dart', stayAlive: true);
    final port = await channel.stream.first as int;
    sqlite3WASMUri = 'http://localhost:$port/sqlite3.wasm';
    sqlite3McUri = 'http://localhost:$port/sqlite3mc.wasm';
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
  Future<SqliteOpenFactory> testFactory({
    String? path,
    String sqlitePath = '',
    SqliteOptions options = const SqliteOptions(),
    EncryptionOptions? encryption,
  }) async {
    await _isInitialized;

    return WebPowerSyncOpenFactory(
      path: path ?? '',
      sqliteOptions: options.copyWith(
        webSqliteOptions: WebSqliteOptions(
          wasmUri: encryption == null ? sqlite3WASMUri : sqlite3McUri,
          workerUri: workerUri,
        ),
      ),
      encryptionOptions: encryption,
    );
  }

  @override
  Future<CommonDatabase> openRawInMemoryDatabase() async {
    await _isInitialized;
    final sqlite = await WasmSqlite3.loadFromUrl(Uri.parse(sqlite3WASMUri));
    sqlite.registerVirtualFileSystem(InMemoryFileSystem(), makeDefault: true);

    return sqlite.openInMemory();
  }
}
