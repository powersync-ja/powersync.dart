import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:code_assets/code_assets.dart';
import 'package:crypto/crypto.dart';
import 'package:hooks/hooks.dart';
import 'package:http/io_client.dart';
import 'package:powersync/src/setup/native.dart';

// If you want to use a local build of the PowerSync SQLite core extension, set
// this to the absolute path of your core extension directory.
const String? _localCoreExtensionCheckout = null;

/// This program is invoked for each target operating system and architecture
/// when compiling a Dart or Flutter app.
///
/// By adding a [CodeAsset] with [DynamicLoadingBundled], we instruct the Dart
/// embedder to include a dynamic library and to use it for looking up symbols
/// in `sqlite3_powersync_init.dart`, which contains a `@Native` method loading
/// the core extension.
///
/// For more information, see [hooks](https://dart.dev/tools/hooks).
void main(List<String> args) async {
  await build(args, (input, output) async {
    if (!input.config.buildCodeAssets) {
      return;
    }

    final File coreExtension;
    if (_localCoreExtensionCheckout case final checkout?) {
      coreExtension = await _useLocalCoreExtension(checkout, input, output);
    } else {
      coreExtension = await _reuseOrDownloadCoreExtension(input);
    }

    output.assets.code.add(CodeAsset(
      package: 'powersync',
      name: 'src/open_factory/native/sqlite3_powersync_init.dart',
      linkMode: DynamicLoadingBundled(),
      file: coreExtension.uri,
    ));
  });
}

Future<File> _reuseOrDownloadCoreExtension(BuildInput input) async {
  final sourceFileName = _fileNameForBuild(input.config.code);
  final digest = assetNameToSha256Hash[sourceFileName]!;

  final targetUri = input.outputDirectoryShared
      .resolve('download-${digest.substring(0, 8)}/');
  final targetDirectory = Directory(targetUri.toFilePath());
  if (!targetDirectory.existsSync()) {
    targetDirectory.createSync();
  }
  final file = File(targetUri
      .resolve(input.config.code.targetOS.libraryFileName(
        'powersync_core',
        DynamicLoadingBundled(),
      ))
      .toFilePath());

  if (file.existsSync()) {
    // Hook is re-run with an existing cache. Does the file match the digest we
    // expect?
    final actualHash = await file.openRead().transform(sha256).first;

    if (actualHash.toString() == digest) {
      // We can reuse the file!
      return file;
    }
  }

  final tmp = File('${file.path}.tmp');
  await tmp.writeAsBytes(await _fetchCoreExtension(sourceFileName, digest));
  tmp.renameSync(file.path);
  return file;
}

Future<Uint8List> _fetchCoreExtension(String fileName, String hash) async {
  final client = IOClient(HttpClient()
    // From Dart 3.11, proxy-related environment variables are passed to
    // hooks. We respect them to ensure we can download these binaries in
    // environments where that's required.
    ..findProxy = HttpClient.findProxyFromEnvironment);
  final uri = Uri.https(
    'github.com',
    'powersync-ja/powersync-sqlite-core/releases/download/$releaseVersion/$fileName',
  );

  try {
    final response = await client.get(uri);
    if (response.statusCode != 200) {
      throw Exception(
          'Could not download $uri, got ${response.statusCode}: ${response.body}');
    }

    final digest = sha256.convert(response.bodyBytes);
    if (digest.toString() != hash) {
      throw Exception(
          'Unexpected digest for $uri, expected $hash got $digest.');
    }

    return response.bodyBytes;
  } finally {
    client.close();
  }
}

/// The name of the file attached to a [core extension release](https://github.com/powersync-ja/powersync-sqlite-core/releases)
/// to use for the target OS/architecture combination.
String _fileNameForBuild(CodeConfig config) {
  Never unsupportedArchitecture() {
    throw UnsupportedError(
      'Target architecture system ${config.targetArchitecture.name} is not '
      'supported by PowerSync for ${config.targetOS.name}. Please consider '
      'filing an issue.',
    );
  }

  String architectureName({
    bool supportArmv7 = false,
    bool supportX86 = false,
    bool supportRiscv = false,
  }) {
    return switch (config.targetArchitecture) {
      Architecture.arm64 => 'aarch64',
      Architecture.x64 => 'x64',
      // These architectures are only supported on some operating systems, so
      // they're guarded by parameters.
      Architecture.arm when supportArmv7 => 'armv7',
      Architecture.ia32 when supportX86 => 'x86',
      Architecture.riscv64 when supportRiscv => 'riscv64gc',
      _ => unsupportedArchitecture(),
    };
  }

  switch (config.targetOS) {
    case OS.android:
      final archName = architectureName(supportArmv7: true, supportX86: true);
      return 'libpowersync_$archName.android.so';
    case OS.iOS:
      if (config.iOS.targetSdk == IOSSdk.iPhoneOS) {
        // Quick sanity check, phyiscal iPhones are arm64-only.
        if (config.targetArchitecture != Architecture.arm64) {
          unsupportedArchitecture();
        }

        return 'libpowersync_aarch64.ios.dylib';
      }

      // We're targeting a simulator, for which we support both arm64 and x64.
      return 'libpowersync_${architectureName()}.ios-sim.dylib';
    case OS.linux:
      final archName = architectureName(
          supportArmv7: true, supportX86: true, supportRiscv: true);
      return 'libpowersync_$archName.linux.so';
    case OS.macOS:
      return 'libpowersync_${architectureName()}.macos.dylib';
    case OS.windows:
      final archName = architectureName(supportX86: true);
      return 'powersync_$archName.dll';
    default:
      throw UnsupportedError(
        'Target operating system ${config.targetOS.name} is not currently '
        'supported by PowerSync. Please consider filing an issue.',
      );
  }
}

Future<File> _useLocalCoreExtension(
    String root, BuildInput input, BuildOutputBuilder output) async {
  final config = input.config.code;
  if (config.targetOS != OS.current ||
      config.targetArchitecture != Architecture.current) {
    // We only need this for local tests anyway.
    throw UnsupportedError(
      'Using a local core extension is not supported for cross-compilation',
    );
  }

  final build = await Process.start(
    'cargo',
    ['build', '-p', 'powersync_loadable'],
    mode: ProcessStartMode.inheritStdio,
    workingDirectory: root,
  );
  if (await build.exitCode case final code when code != 0) {
    throw StateError('Rust build failed: exit code $code');
  }

  final outputName = config.targetOS.dylibFileName('powersync');
  final rootUri = Uri.directory(root);
  final library = rootUri.resolve('target/debug/$outputName');
  final depsFile = File.fromUri(
    library.resolve(
      Platform.isWindows ? 'powersync.d' : 'libpowersync.d',
    ),
  );

  // Parse generated depfile to re-run this hook when a Rust source has changed.
  // The format is "target: dep1 dep2 ...".
  final depsContent = depsFile.readAsStringSync();
  final [_, depsList] = depsContent.split(': ');
  // Paths with spaces are escaped as "\ " in the Makefile format.
  final deps = depsList.split(RegExp(r'(?<!\\) '));
  for (final dep in deps) {
    final trimmed = dep.trim().replaceAll(r'\ ', ' ');
    if (trimmed.isNotEmpty) {
      output.dependencies.add(Uri.file(trimmed));
    }
  }
  // Also invalidate build when Cargo.lock changes.
  output.dependencies.add(rootUri.resolve('Cargo.lock'));

  return File.fromUri(library);
}
