import 'dart:convert';
import 'dart:io';
import 'package:pubspec_parse/pubspec_parse.dart';

void main() async {
  final root = Directory.current.uri;
  print('Project root: ${root.toFilePath()}');

  final wasmPath = '${root.toFilePath()}web/sqlite3.wasm';

  final workerPath = '${root.toFilePath()}web/powersync_db.worker.js';

  final packageConfigFile = File.fromUri(
    root.resolve('.dart_tool/package_config.json'),
  );
  dynamic packageConfig;
  try {
    packageConfig = json.decode(await packageConfigFile.readAsString());
  } on FileSystemException {
    print('Missing .dart_tool/package_config.json');
    print('Run `flutter pub get` first.');
    exit(1);
  } on FormatException {
    print('Invalid .dart_tool/package_config.json');
    print('Run `flutter pub get` first.');
    exit(1);
  }

  final powersyncPkg = getPackageFromConfig(packageConfig, 'powersync');

  final powersyncRoot =
      packageConfigFile.uri.resolve(powersyncPkg['rootUri'] ?? '');
  print('Using package:powersync from ${powersyncRoot.toFilePath()}');

  String pubspec =
      File('${powersyncRoot.toFilePath()}/pubspec.yaml').readAsStringSync();
  Pubspec parsed = Pubspec.parse(pubspec);
  final powersyncVersion = parsed.version?.toString();
  if (powersyncVersion == null) {
    print('Powersync version not found');
    print('Run `flutter pub get` first.');
    exit(1);
  }

  //TODO: Get sqlite3.dart version from pubspec.yaml
  final sqlite3Pkg = getPackageFromConfig(packageConfig, 'sqlite3');

  final sqlite3Root =
      packageConfigFile.uri.resolve(sqlite3Pkg['rootUri'] ?? '');
  print('Using package:sqlite3 from ${sqlite3Root.toFilePath()}');

  pubspec = File('${sqlite3Root.toFilePath()}/pubspec.yaml').readAsStringSync();
  parsed = Pubspec.parse(pubspec);
  final sqlite3Version = parsed.version?.toString();
  if (sqlite3Version == null) {
    print('Sqlite3 version not found');
    print('Run `flutter pub get` first.');
    exit(1);
  }

  //TODO: Use `sqlite3Version` to get the correct sqlite3.wasm
  final sqliteUrl =
      'https://github.com/powersync-ja/sqlite3.dart/releases/download/v0.1.0/sqlite3.wasm';

  final workerUrl =
      'https://github.com/powersync-ja/powersync.dart/releases/download/v$powersyncVersion/powersync_db.worker.js';

  await downloadFile(sqliteUrl, wasmPath);
  await downloadFile(workerUrl, workerPath);
}

dynamic getPackageFromConfig(dynamic packageConfig, String packageName) {
  final pkg = (packageConfig['packages'] ?? []).firstWhere(
    (e) => e['name'] == packageName,
    orElse: () => null,
  );
  if (pkg == null) {
    print('dependency on package:powersync is required');
    exit(1);
  }
  return pkg;
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
