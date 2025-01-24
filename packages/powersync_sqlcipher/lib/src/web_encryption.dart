import 'package:powersync_core/sqlite_async.dart';
import 'package:powersync_core/web.dart';

import '../powersync.dart';

final class _WebEncryptionFactory extends PowerSyncSQLCipherOpenFactory
    with WebSqliteOpenFactory {
  _WebEncryptionFactory({
    required super.path,
    required super.key,
    super.sqliteOptions,
  }) : super.internal();

  @override
  List<String> pragmaStatements(SqliteOpenOptions options) {
    final basePragmaStatements = super.pragmaStatements(options);
    return [
      // Set the encryption key as the first statement
      "PRAGMA KEY = ${quoteString(key)}",
      // Include the default statements afterwards
      for (var statement in basePragmaStatements) statement
    ];
  }

  @override
  Future<ConnectToRecommendedResult> connectToWorker(
      WebSqlite sqlite, String name) async {
    return sqlite.connectToRecommended(
      name,
      additionalOptions: PowerSyncAdditionalOpenOptions(
        useMultipleCiphersVfs: true,
      ),
    );
  }
}

PowerSyncSQLCipherOpenFactory cipherFactory({
  required String path,
  required String key,
  required SqliteOptions options,
}) {
  return _WebEncryptionFactory(path: path, key: key, sqliteOptions: options);
}
