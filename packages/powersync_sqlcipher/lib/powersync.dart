/// PowerSync with Encryption for Flutter.
///
/// Use [PowerSyncSQLCipherOpenFactory] to open an encrypted database.
library;

import 'package:powersync_core/sqlite_async.dart';
import 'package:powersync_sqlcipher/powersync.dart';

export 'package:powersync_core/powersync_core.dart';

import 'src/stub.dart'
    if (dart.library.js_interop) 'src/web_encryption.dart'
    if (dart.library.ffi) 'src/sqlcipher.dart';

/// A factory for opening a database with SQLCipher encryption.
/// An encryption [key] is required to open the database.
abstract interface class PowerSyncSQLCipherOpenFactory
    extends PowerSyncOpenFactory {
  factory PowerSyncSQLCipherOpenFactory(
      {required String path,
      required String key,
      SqliteOptions sqliteOptions = powerSyncDefaultSqliteOptions}) {
    return cipherFactory(path: path, key: key, options: sqliteOptions);
  }

  String get key;
}
