import 'package:powersync/src/open_factory/abstract_powersync_open_factory.dart';
import 'package:powersync/src/uuid.dart';
import 'package:sqlite_async/sqlite3_common.dart';

class PowerSyncOpenFactory extends AbstractPowerSyncOpenFactory {
  PowerSyncOpenFactory({
    required super.path,
    super.sqliteOptions,
  });

  @override
  void enableExtension() {
    // No op for web
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
}
