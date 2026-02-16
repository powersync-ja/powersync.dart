import 'package:sqlite_async/sqlite3_common.dart';

/// A parsed (major, minor, patch) version triple representing a version of the
/// loaded core extension.
extension type const PowerSyncCoreVersion((int, int, int) _tuple) {
  int get major => _tuple.$1;
  int get minor => _tuple.$2;
  int get patch => _tuple.$3;

  int compareTo(PowerSyncCoreVersion other) {
    return switch (major.compareTo(other.major)) {
      0 => switch (minor.compareTo(other.minor)) {
          0 => patch.compareTo(other.patch),
          var other => other,
        },
      var other => other,
    };
  }

  bool operator <(PowerSyncCoreVersion other) => compareTo(other) < 0;
  bool operator >=(PowerSyncCoreVersion other) => compareTo(other) >= 0;

  String get versionString => '$major.$minor.$patch';

  void checkSupported() {
    const isWeb = bool.fromEnvironment('dart.library.js_interop');

    if (this < minimum || this >= maximumExclusive) {
      var message =
          'Unsupported powersync extension version. This version of the '
          'PowerSync SDK needs >=${minimum.versionString} '
          '<${maximumExclusive.versionString}, '
          'but detected version $versionString.';
      if (isWeb) {
        message +=
            '\nTry downloading the updated assets: https://docs.powersync.com/client-sdk-references/flutter/flutter-web-support#assets';
      }

      throw SqliteException(1, message);
    }
  }

  /// Parses the output of `powersync_rs_version()`, e.g. `0.3.9/5d64f366`, into
  /// a [PowerSyncCoreVersion].
  static PowerSyncCoreVersion parse(String version) {
    try {
      final [major, minor, patch] =
          version.split(RegExp(r'[./]')).take(3).map(int.parse).toList();

      return PowerSyncCoreVersion((major, minor, patch));
    } catch (e) {
      throw SqliteException(1,
          'Unsupported powersync extension version. Need >=0.2.0 <1.0.0, got: $version. Details: $e');
    }
  }

  /// The minimum version of the sqlite core extensions we support. We check
  /// this version when opening databases to fail early and with an actionable
  /// error message.
  // Note: When updating this, also update:
  //
  //  - scripts/init_powersync_core_binary.dart
  //  - scripts/download_core_binary_demos.dart
  //  - packages/sqlite3_wasm_build/build.sh
  //  - Android and Darwin (CocoaPods and SwiftPM) in powersync_flutter_libs
  static const minimum = PowerSyncCoreVersion((0, 4, 11));

  /// The first version of the core extensions that this version of the Dart
  /// SDK doesn't support.
  static const maximumExclusive = PowerSyncCoreVersion((1, 0, 0));
}
