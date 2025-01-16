import 'dart:async';

import 'package:powersync_core/src/open_factory/abstract_powersync_open_factory.dart';
import 'package:powersync_core/src/uuid.dart';
import 'package:sqlite_async/sqlite3_common.dart';
import 'package:sqlite_async/sqlite3_web.dart';
import 'package:sqlite_async/sqlite_async.dart';
import 'package:sqlite_async/web.dart';

import '../../web/worker_utils.dart';

/// Web implementation for [AbstractPowerSyncOpenFactory]
class PowerSyncOpenFactory extends AbstractPowerSyncOpenFactory
    implements WebSqliteOpenFactory {
  PowerSyncOpenFactory({
    required super.path,
    super.sqliteOptions,
  });

  @override
  Future<WebSqlite> openWebSqlite(WebSqliteOptions options) async {
    return WebSqlite.open(
      wasmModule: Uri.parse(sqliteOptions.webSqliteOptions.wasmUri),
      worker: Uri.parse(sqliteOptions.webSqliteOptions.workerUri),
      controller: PowerSyncAsyncSqliteController(),
    );
  }

  @override
  void enableExtension() {
    // No op for web
  }

  @override
  Future<SqliteConnection> openConnection(SqliteOpenOptions options) async {
    var conn = await super.openConnection(options);
    for (final statement in super.pragmaStatements(options)) {
      await conn.execute(statement);
    }

    return super.openConnection(options);
  }

  @override

  /// This is only called when synchronous connections are created in the same
  /// Dart/JS context. Worker runners need to setupFunctions manually
  setupFunctions(CommonDatabase db) {
    super.setupFunctions(db);

    db.createFunction(
      functionName: 'uuid',
      argumentCount: const AllowedArgumentCount(0),
      function: (args) {
        return uuid.v4();
      },
    );
    db.createFunction(
      // Postgres compatibility
      functionName: 'gen_random_uuid',
      argumentCount: const AllowedArgumentCount(0),
      function: (args) => uuid.v4(),
    );
  }

  @override
  String getLibraryForPlatform({String? path}) {
    // no op for web
    return "";
  }
}
