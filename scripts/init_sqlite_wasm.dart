/// Downloads sqlite3.wasm and copies it to all demo folders
import 'dart:io';

final sqliteUrl =
    'https://github.com/powersync-ja/sqlite3.dart/releases/download/v0.1.0/sqlite3.wasm';

void main() async {
  // Create assets directory if it doesn't exist
  final assetsDir = Directory('assets');
  if (!await assetsDir.exists()) {
    await assetsDir.create();
  }

  final sqliteFilename = 'sqlite3.wasm';
  final sqlitePath = 'assets/$sqliteFilename';

  // Download sqlite3.wasm
  await downloadFile(sqliteUrl, sqlitePath);

  await for (var entity in Directory('demos').list()) {
    if (entity is Directory) {
      var demoDir = entity;
      var webDir = Directory('${demoDir.path}/web');
      if (await webDir.exists()) {
        await File(sqlitePath).copy('${webDir.path}/$sqliteFilename');
        print('Copied $sqlitePath to ${webDir.path}');
      }
    }
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
