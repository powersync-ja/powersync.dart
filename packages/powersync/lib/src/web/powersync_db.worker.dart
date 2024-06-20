/// This file needs to be compiled to JavaScript with the command
/// dart compile js -O4 packages/powersync/lib/src/web/powersync_db.worker.dart -o assets/db_worker.js
/// The output should then be included in each project's `web` directory

library;

import 'dart:js_interop';

import 'package:sqlite_async/sqlite3_web_worker.dart';
import 'package:sqlite_async/sqlite3_web.dart';
import 'package:sqlite_async/sqlite3_wasm.dart';

import 'worker_utils.dart';

void main() {
  WebSqlite.workerEntrypoint(controller: PowerSyncAsyncSqliteController());
}

final class PowerSyncAsyncSqliteController extends AsyncSqliteController {
  @override
  Future<WorkerDatabase> openDatabase(
      WasmSqlite3 sqlite3, String path, String vfs) async {
    final db = sqlite3.open(path, vfs: vfs);
    setupPowerSyncDatabase(db);

    return AsyncSqliteDatabase(database: db);
  }

  @override
  Future<JSAny?> handleCustomRequest(
      ClientConnection connection, JSAny? request) {
    throw UnimplementedError();
  }
}
