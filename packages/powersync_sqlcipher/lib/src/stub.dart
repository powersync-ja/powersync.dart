import '../powersync.dart';
import '../sqlite_async.dart';

PowerSyncSQLCipherOpenFactory cipherFactory({
  required String path,
  required String key,
  required SqliteOptions options,
}) {
  throw UnsupportedError('Unsupported platform for powersync_sqlcipher');
}
