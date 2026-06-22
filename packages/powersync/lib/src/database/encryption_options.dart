import 'package:sqlite3/common.dart';
import 'package:sqlite_async/utils.dart';

const _isCompilingToJavaScript = identical(0, 0.0);
const _isDart2Wasm = bool.fromEnvironment('dart.tool.dart2wasm');
const _isWeb = _isCompilingToJavaScript || _isDart2Wasm;

/// Options controlling if and how a database should be encrypted.
///
/// ## Setup
///
/// Enabling encryption requires additional setup depending on the target
/// platform.
///
/// ### Native
///
/// On native platforms, the `sqlite3` package provides a copy of SQLite with
/// your app. To use encryption, we need to replace SQLite with
/// [SQLite3MultipleCiphers](https://utelle.github.io/SQLite3MultipleCiphers/)
/// or [SQLCipher](https://www.zetetic.net/sqlcipher/).
/// To enable that, add this to your `pubspec.yaml`:
///
/// ```yaml
/// hooks:
///   user_defines:
///     sqlite3:
///       source: sqlite3mc # or sqlcipher
/// ```
///
/// If you're using pub workspaces, this needs to be added to the `pubspec.yaml`
/// defining the workspace.
///
/// ### Web
///
/// Using SQLite3MultipleCiphers is also required for the web. Each
/// [release](https://github.com/powersync-ja/powersync.dart/releases) or the
/// PowerSync SDK provides both a `sqlite3.wasm` and a `sqlite3mc.wasm` file.
///
/// To use encryption, download `sqlite3mc.wasm` as `web/sqlite3.wasm`. If you
/// use the `powersync:setup_web` tool to download that file, pass the
/// `--encryption` option.
///
/// Note that SQLCipher is not available on the web.
final class EncryptionOptions {
  /// The key used to encrypt the database file.
  ///
  /// To change the key of an existing encrypted database, first open it with
  /// the old key, then run a [`PRAGMA rekey`](https://utelle.github.io/SQLite3MultipleCiphers/docs/configuration/config_sql_pragmas/#pragma-rekey--hexrekey)
  /// statement and finally re-open the database with the new key.
  final String key;

  /// Whether to use an encryption scheme that is compatible with SQLCipher-
  /// based databases when SQLite3MultipleCiphers is enabled.
  ///
  /// For backwards-compatibility with SQLCipher and the `powersync_sqlcipher`
  /// package, this is enabled by default on native platforms. If you've never
  /// used that package or SQLCipher, this can be disabled.
  final bool sqlcipherCompatibility;

  const EncryptionOptions({
    required this.key,
    this.sqlcipherCompatibility = !_isWeb,
  });

  Iterable<String> pragmaStatements({
    EncryptedSqliteVariant variant =
        EncryptedSqliteVariant.sqlite3MultipleCiphers,
  }) sync* {
    if (sqlcipherCompatibility &&
        variant == EncryptedSqliteVariant.sqlite3MultipleCiphers) {
      yield "PRAGMA cipher = 'sqlcipher'";
      yield 'PRAGMA legacy = 4';
    }

    // https://utelle.github.io/SQLite3MultipleCiphers/docs/configuration/config_sql_pragmas/#pragma-key--hexkey
    yield 'PRAGMA key = ${quoteString(key)}';
  }

  /// Throws if the `cipher` pragma doesn't exist, as that indicates that
  /// SQLite3MultipleCiphers is not available.
  @Deprecated('Unused in PowerSync SDK, check '
      'EncryptedSqliteVariant.resolveOnDatabase instead')
  static void checkHasCipherPragma(CommonDatabase database) {
    if (database.select('pragma cipher').isEmpty) {
      throw UnsupportedError(
        'Tried to use encryption, but SQLite3MultipleCiphers is not available. '
        'Consult the documentation on EncryptionOptions on how to resolve this.',
      );
    }
  }
}

/// A fork of SQLite with encryption support.
enum EncryptedSqliteVariant {
  /// [SQLCipher](https://www.zetetic.net/sqlcipher/) can encrypt databases with
  /// AES.
  ///
  /// Encrypting databases with SQLCipher can be more performant than
  /// [sqlite3MultipleCiphers] because it uses optimized system encryption
  /// libraries (on Apple platform) and OpenSSL (on other platforms).
  ///
  /// Note that SQLCipher is not available on the web.
  sqlcipher,

  /// [SQLite3 Multiple Ciphers](https://utelle.github.io/SQLite3MultipleCiphers/)
  /// provides compatibility with multiple encryption schemes from a single
  /// build.
  ///
  /// On the web, this is the only option available to encrypt databases.
  sqlite3MultipleCiphers;

  /// The [EncryptedSqliteVariant] enabled on the database, or null.
  static EncryptedSqliteVariant? resolveOnDatabase(CommonDatabase db) {
    if (db.select('pragma cipher').isNotEmpty) {
      return EncryptedSqliteVariant.sqlite3MultipleCiphers;
    } else if (db.select('pragma cipher_version').isNotEmpty) {
      return EncryptedSqliteVariant.sqlcipher;
    } else {
      return null;
    }
  }
}
