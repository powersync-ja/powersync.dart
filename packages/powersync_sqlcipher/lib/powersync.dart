/// PowerSync with Encryption for Flutter.
///
/// Use [PowerSyncSQLCipherOpenFactory] to open an encrypted database.
library;

export 'package:powersync_core/powersync_core.dart';

export 'src/stub.dart'
    if (dart.library.js_interop) 'src/web_encryption.dart'
    if (dart.library.ffi) 'src/sqlcipher.dart';
