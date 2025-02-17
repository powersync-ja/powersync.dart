/// Downloads the powersync-core dynamic library to run the demos using melos
/// This is only necessary in the monorepo setup
import 'dart:io';

final coreUrl =
    'https://github.com/powersync-ja/powersync-sqlite-core/releases/download/v0.3.10';

void main() async {
  final powersyncLibsLinuxPath = "packages/powersync_flutter_libs/linux";
  final powersyncLibsWindowsPath = "packages/powersync_flutter_libs/windows";

  final linuxArm64FileName = "libpowersync_aarch64.so";
  final linuxX64FileName = "libpowersync_x64.so";
  final windowsX64FileName = "powersync_x64.dll";

  // Download dynamic library
  await downloadFile("$coreUrl/$linuxArm64FileName",
      "$powersyncLibsLinuxPath/$linuxArm64FileName");
  await downloadFile("$coreUrl/$linuxX64FileName",
      "$powersyncLibsLinuxPath/$linuxX64FileName");
  await downloadFile("$coreUrl/$windowsX64FileName",
      "$powersyncLibsWindowsPath/$windowsX64FileName");
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
