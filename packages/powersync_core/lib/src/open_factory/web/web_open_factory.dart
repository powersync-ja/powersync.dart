import 'dart:async';

import 'package:sqlite3_web/sqlite3_web.dart';
import 'package:sqlite_async/sqlite_async.dart';
import 'package:sqlite_async/web.dart';

import '../../web/worker_utils.dart';

/// PowerSync-specific [WebSqliteOpenFactory].
///
/// This mostly installs a [PowerSyncAsyncSqliteController] to ensure we use
/// an encrypted VFS where necessary.
base class WebPowerSyncOpenFactory extends WebSqliteOpenFactory {
  WebPowerSyncOpenFactory({required super.path, super.sqliteOptions});

  @override
  Future<WebSqlite> openWebSqlite(WebSqliteOptions options) async {
    return WebSqlite.open(
      wasmModule: Uri.parse(sqliteOptions.webSqliteOptions.wasmUri),
      workers: WorkerConnector.defaultWorkers(
          Uri.parse(sqliteOptions.webSqliteOptions.workerUri)),
      controller: PowerSyncAsyncSqliteController(),
      handleCustomRequest: handleCustomRequest,
    );
  }
}
