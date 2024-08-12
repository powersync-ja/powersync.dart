import 'package:powersync/sqlite3_common.dart';
import 'package:powersync/src/open_factory/common_db_functions.dart';
import 'package:uuid/uuid.dart';

// Registers custom SQLite functions for the SQLite connection
void setupPowerSyncDatabase(CommonDatabase database) {
  setupCommonDBFunctions(database);
  final uuid = Uuid();

  database.createFunction(
    functionName: 'uuid',
    argumentCount: const AllowedArgumentCount(0),
    function: (args) {
      return uuid.v4();
    },
  );
  database.createFunction(
    // Postgres compatibility
    functionName: 'gen_random_uuid',
    argumentCount: const AllowedArgumentCount(0),
    function: (args) => uuid.v4(),
  );
  database.createFunction(
    functionName: 'powersync_sleep',
    argumentCount: const AllowedArgumentCount(1),
    function: (args) {
      // Can't perform synchronous sleep on web
      final millis = args[0] as int;
      return millis;
    },
  );

  database.createFunction(
    functionName: 'powersync_connection_name',
    argumentCount: const AllowedArgumentCount(0),
    function: (args) {
      return 'N/A';
    },
  );
}
