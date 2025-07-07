import 'package:logging/logging.dart';
import 'package:powersync_core/src/database/powersync_database_impl.dart';
import 'package:powersync_core/src/database/powersync_db_mixin.dart';
import 'package:powersync_core/src/open_factory/abstract_powersync_open_factory.dart';
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
  /// Open a [PowerSyncDatabase].
  ///
  /// Only a single [PowerSyncDatabase] per [path] should be opened at a time.
  ///
  /// The specified [schema] is used for the database.
  ///
  /// A connection pool is used by default, allowing multiple concurrent read
  /// transactions, and a single concurrent write transaction. Write transactions
  /// do not block read transactions, and read transactions will see the state
  /// from the last committed write transaction.
  ///
  /// A maximum of [maxReaders] concurrent read transactions are allowed.
  ///
  /// [logger] defaults to [autoLogger], which logs to the console in debug builds.
  factory PowerSyncDatabase(
      {required Schema schema,
      required String path,
      Logger? logger,
      @Deprecated("Use [PowerSyncDatabase.withFactory] instead.")
      // ignore: deprecated_member_use_from_same_package
      SqliteConnectionSetup? sqliteSetup}) {
    return PowerSyncDatabaseImpl(
        schema: schema,
        path: path,
        logger: logger,
        // ignore: deprecated_member_use_from_same_package
        sqliteSetup: sqliteSetup);
  }

  /// Open a [PowerSyncDatabase] with a [PowerSyncOpenFactory].
  ///
  /// The factory determines which database file is opened, as well as any
  /// additional logic to run inside the database isolate before or after opening.
  ///
  /// Subclass [PowerSyncOpenFactory] to add custom logic to this process.
  ///
  /// [logger] defaults to [autoLogger], which logs to the console in debug builds.
  factory PowerSyncDatabase.withFactory(DefaultSqliteOpenFactory openFactory,
      {required Schema schema,
      int maxReaders = SqliteDatabase.defaultMaxReaders,
      Logger? logger}) {
    return PowerSyncDatabaseImpl.withFactory(openFactory,
        schema: schema, maxReaders: maxReaders, logger: logger);
  }

  /// Open a PowerSyncDatabase on an existing [SqliteDatabase].
  ///
  /// Migrations are run on the database when this constructor is called.
  ///
  /// [logger] defaults to [autoLogger], which logs to the console in debug builds.
  factory PowerSyncDatabase.withDatabase({
    required Schema schema,
    required SqliteDatabase database,
    Logger? logger,
    @Deprecated("Use [logger] instead") Logger? loggers,
  }) {
    return PowerSyncDatabaseImpl.withDatabase(
      schema: schema,
      database: database,
      logger: loggers ?? logger,
    );
  }
}
