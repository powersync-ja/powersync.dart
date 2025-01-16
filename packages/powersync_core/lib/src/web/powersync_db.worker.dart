/// This file needs to be compiled to JavaScript with the command
/// dart compile js -O4 packages/powersync/lib/src/web/powersync_db.worker.dart -o assets/db_worker.js
/// The output should then be included in each project's `web` directory

library;

import 'package:sqlite_async/sqlite3_web.dart';

import 'worker_utils.dart';

void main() {
  WebSqlite.workerEntrypoint(controller: PowerSyncAsyncSqliteController());
}
