/// This file needs to be compiled to JavaScript with the command
/// dart compile js -O4 packages/powersync/lib/src/web/powersync_db.worker.dart -o assets/db_worker.js
/// The output should then be included in each project's `web` directory

library;

import 'dart:js_interop';

import 'package:mutex/mutex.dart';
import 'package:sqlite3/wasm.dart';

import 'package:sqlite_async/sqlite3_web_worker.dart';
import 'package:sqlite3_web/sqlite3_web.dart';

import 'worker_utils.dart';

void main() {
  WebSqlite.workerEntrypoint(controller: _AsyncSqliteController());
}

/// TODO this could be exported from sqlite_async
final class _AsyncSqliteController extends DatabaseController {
  @override
  Future<WorkerDatabase> openDatabase(WasmSqlite3 sqlite3, String vfs) async {
    final db = sqlite3.open('/app.db', vfs: vfs);
    setupPowerSyncDatabase(db);

    return _AsyncSqliteDatabase(database: db);
  }

  @override
  Future<JSAny?> handleCustomRequest(
      ClientConnection connection, JSAny? request) {
    throw UnimplementedError();
  }
}

class _AsyncSqliteDatabase extends WorkerDatabase {
  @override
  final CommonDatabase database;

  // This mutex is only used for lock requests from clients. Clients only send
  // these requests for shared workers, so we can assume each database is only
  // opened once and we don't need web locks here.
  final mutex = ReadWriteMutex();

  _AsyncSqliteDatabase({required this.database});

  @override
  Future<JSAny?> handleCustomRequest(
      ClientConnection connection, JSAny? request) async {
    final message = request as CustomDatabaseMessage;

    switch (message.kind) {
      case CustomDatabaseMessageKind.requestSharedLock:
        await mutex.acquireRead();
      case CustomDatabaseMessageKind.requestExclusiveLock:
        await mutex.acquireWrite();
      case CustomDatabaseMessageKind.releaseLock:
        mutex.release();
      case CustomDatabaseMessageKind.lockObtained:
        throw UnsupportedError('This is a response, not a request');
      case CustomDatabaseMessageKind.getAutoCommit:
        return database.autocommit.toJS;
    }

    return CustomDatabaseMessage(CustomDatabaseMessageKind.lockObtained);
  }
}
