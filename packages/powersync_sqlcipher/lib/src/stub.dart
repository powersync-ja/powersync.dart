import '../powersync.dart';
import 'shared.dart';

/// A factory for opening a database with SQLCipher encryption.
/// An encryption [key] is required to open the database.
class PowerSyncSQLCipherOpenFactory extends PowerSyncOpenFactory {
  PowerSyncSQLCipherOpenFactory({
    required super.path,
    required this.key,
    super.sqliteOptions = defaultOptions,
  }) {
    throw UnsupportedError('Unsupported platform for powersync_sqlcipher');
  }

  final String key;
}
