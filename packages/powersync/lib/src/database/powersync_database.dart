import 'package:logging/logging.dart';
import 'package:powersync/src/database/powersync_database_impl.dart';
import 'package:powersync/src/database/powersync_db_mixin.dart';
import 'package:sqlite_async/sqlite_async.dart';

import '../schema.dart';

/// A PowerSync managed database.
///
/// Use one instance per database file.
///
/// Use [PowerSyncDatabase.connect] to connect to the PowerSync service,
/// to keep the local database in sync with the remote database.
///
/// All changes to local tables are automatically recorded, whether connected
/// or not. Once connected, the changes are uploaded.
abstract class PowerSyncDatabase
    with SqliteQueries, PowerSyncDatabaseMixin
    implements SqliteConnection {
  factory PowerSyncDatabase(
      {required Schema schema, required String path, Logger? logger}) {
    return PowerSyncDatabaseImpl(schema: schema, path: path, logger: logger);
  }

  factory PowerSyncDatabase.withFactory(DefaultSqliteOpenFactory openFactory,
      {required Schema schema,
      int maxReaders = SqliteDatabase.defaultMaxReaders,
      Logger? logger}) {
    return PowerSyncDatabaseImpl.withFactory(openFactory,
        schema: schema, logger: logger);
  }

  factory PowerSyncDatabase.withDatabase(
      {required Schema schema,
      required SqliteDatabase database,
      Logger? loggers}) {
    return PowerSyncDatabaseImpl.withDatabase(
        schema: schema, database: database);
  }
}
