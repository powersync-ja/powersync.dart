import '../sqlite_async.dart';

const defaultOptions = SqliteOptions(
  webSqliteOptions: WebSqliteOptions(
      wasmUri: 'sqlite3mc.wasm', workerUri: 'powersync_db.worker.js'),
);

mixin BaseSQLCipherFactoryMixin on AbstractDefaultSqliteOpenFactory {
  String get key;

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
}
