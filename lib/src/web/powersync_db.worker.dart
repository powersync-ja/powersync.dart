/// This file needs to be compiled to JavaScript with the command
/// dart compile js -O4 lib/src/web/powersync_db.worker.dart -o build/powersync_db.worker.js
/// The output should then be included in each project's `web` directory

import 'package:powersync/src/open_factory/common_db_functions.dart';
import 'package:sqlite_async/drift.dart';
import 'package:sqlite_async/sqlite3_common.dart';
import 'package:uuid/uuid.dart';

void setupDatabase(CommonDatabase database) {
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
      final millis = args[0] as int;
      // TODO
      // sleep(Duration(milliseconds: millis));
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

void main() {
  WasmDatabase.workerMainForOpen(
    setupAllDatabases: setupDatabase,
  );
}
