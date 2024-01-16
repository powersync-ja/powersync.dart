import 'dart:async';
import 'dart:html';

import 'package:sqlite_async/sqlite_async.dart';
import 'package:sqlite_async/sqlite3_common.dart';
import '../open_factory_interface.dart' as open_factory;
import '../../uuid.dart';

class PowerSyncOpenFactory
    extends open_factory.AbstractPowerSyncOpenFactory<CommonDatabase> {
  PowerSyncOpenFactory({
    required super.path,
    super.sqliteOptions,
  });

  void enableExtension() {
    // No op for web
  }

  @override
  setupFunctions(CommonDatabase db) {
    super.setupFunctions(db);

    db.createFunction(
      functionName: 'uuid',
      argumentCount: const AllowedArgumentCount(0),
      function: (args) {
        final id = uuid.v4();
        print('Creating a uuid' + id);
        return id;
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
  FutureOr<CommonDatabase> open(SqliteOpenOptions options) async {
    final worker = SharedWorker('worker.js');
    worker.port!.postMessage('ddd');

    final db = await super.open(options);
    setupFunctions(db);
    return db;
  }
}
