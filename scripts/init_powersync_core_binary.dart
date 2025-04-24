/// Downloads the powersync dynamic library and copies it to the powersync_core package directory
/// This is only necessary for running unit tests in the powersync_core package
import 'dart:ffi';
import 'dart:io';

import 'package:melos/melos.dart';

final sqliteUrl =
    'https://github.com/powersync-ja/powersync-sqlite-core/releases/download/v0.3.13';

void main() async {
  final sqliteCoreFilename = getLibraryForPlatform();
  final powersyncPath = "packages/powersync_core";
  final sqliteCorePath = '$powersyncPath/$sqliteCoreFilename';

  // Download dynamic library
  await downloadFile("$sqliteUrl/$sqliteCoreFilename", sqliteCorePath);

  final originalFile = File(sqliteCorePath);

  try {
    final newFileName = getFileNameForPlatform();
    if (await originalFile.exists()) {
      try {
        // Rename the original file to the new file name
        await originalFile.rename("$powersyncPath/$newFileName");
        print(
            'File renamed successfully from $sqliteCoreFilename to $newFileName');
      } catch (e) {
        throw IOException('Error renaming file: $e');
      }
    } else {
      throw IOException('File $sqliteCoreFilename does not exist.');
    }
  } on IOException catch (e) {
    print(e.message);
  }
}

String getFileNameForPlatform() {
  switch (Abi.current()) {
    case Abi.macosArm64:
    case Abi.macosX64:
      return 'libpowersync.dylib';
    case Abi.linuxX64:
    case Abi.linuxArm64:
      return 'libpowersync.so';
    case Abi.windowsX64:
      return 'powersync.dll';
    default:
      throw IOException(
        'Unsupported processor architecture "${Abi.current()}". '
        'Please open an issue on GitHub to request it.',
      );
  }
}

Future<void> downloadFile(String url, String savePath) async {
  print('Downloading: $url');
  var httpClient = HttpClient();
  var request = await httpClient.getUrl(Uri.parse(url));
  var response = await request.close();
  if (response.statusCode == HttpStatus.ok) {
    var file = File(savePath);
    await response.pipe(file.openWrite());
  } else {
    print(
        'Failed to download file: ${response.statusCode} ${response.reasonPhrase}');
  }
}

String getLibraryForPlatform() {
  switch (Abi.current()) {
    case Abi.macosArm64:
      return 'libpowersync_aarch64.dylib';
    case Abi.macosX64:
      return 'libpowersync_x64.dylib';
    case Abi.linuxX64:
      return 'libpowersync_x64.so';
    case Abi.linuxArm64:
      return 'libpowersync_aarch64.so';
    case Abi.windowsX64:
      return 'powersync_x64.dll';
    case Abi.windowsArm64:
      throw IOException('ARM64 Windows is not supported. '
          'Please use an x86_64 Windows machine or open a GitHub issue to request it');
    default:
      throw IOException(
        'Unsupported processor architecture "${Abi.current()}". '
        'Please open an issue on GitHub to request it.',
      );
  }
}
