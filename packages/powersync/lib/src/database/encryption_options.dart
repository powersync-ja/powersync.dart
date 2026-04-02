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
/// [SQLite3MultipleCiphers](https://utelle.github.io/SQLite3MultipleCiphers/).
/// To enable that, add this to your `pubspec.yaml`:
///
/// ```yaml
/// hooks:
///   user_defines:
///     sqlite3:
///       source: sqlite3mc
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
final class EncryptionOptions {
  /// The key used to encrypt the database file.
  final String key;

  /// Whether to use an encryption scheme that is compatible with SQLCipher-
  /// based databases.
  ///
  /// For backwards-compatibility with the `powersync_sqlcipher` package, this
  /// is enabled by default on native platforms. If you've never used that
  /// package, this can be disabled.
  final bool sqlcipherCompatibility;

  const EncryptionOptions({
    required this.key,
    this.sqlcipherCompatibility = !_isWeb,
  });

  Iterable<String>? pragmaStatements() sync* {
    if (sqlcipherCompatibility) {
      yield "PRAGMA cipher = 'sqlcipher'";
      yield 'PRAGMA legacy = 4';
    }

    // https://utelle.github.io/SQLite3MultipleCiphers/docs/configuration/config_sql_pragmas/#pragma-key--hexkey
    yield 'PRAGMA key = ${quoteString(key)}';
  }

  /// Throws if the `cipher` pragma doesn't exist, as that indicates that
  /// SQLite3MultipleCiphers is not available.
  static void checkHasCipherPragma(CommonDatabase database) {
    if (database.select('pragma cipher').isEmpty) {
      throw UnsupportedError(
        'Tried to use encryption, but SQLite3MultipleCiphers is not available. '
        'Consult the documentation on EncryptionOptions on how to resolve this.',
      );
    }
  }
}
