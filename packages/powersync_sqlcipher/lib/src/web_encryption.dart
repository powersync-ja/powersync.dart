import 'package:powersync_core/sqlite_async.dart';
import 'package:powersync_core/web.dart';

import '../powersync.dart';

final class _WebEncryptionFactory extends PowerSyncWebOpenFactory
    implements PowerSyncSQLCipherOpenFactory {
  @override
  final String key;

  _WebEncryptionFactory({
    required super.path,
    required this.key,
    super.sqliteOptions,
  });

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
