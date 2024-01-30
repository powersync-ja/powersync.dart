import 'package:sqlite_async/sqlite3_common.dart';
import '../abstract_powersync_open_factory.dart' as open_factory;
import '../../uuid.dart';

class PowerSyncOpenFactory extends open_factory.AbstractPowerSyncOpenFactory {
  PowerSyncOpenFactory({
    required super.path,
    super.sqliteOptions,
  });

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
}
