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

  final powersyncPackageName = 'powersync';

  final powersyncPkg =
      getPackageFromConfig(packageConfig, powersyncPackageName);

  final powersyncVersion =
      getPubspecVersion(packageConfigFile, powersyncPkg, powersyncPackageName);

  final sqlitePackageName = 'sqlite3';

  //TODO: Get sqlite3.dart version from pubspec.yaml
  final sqlite3Pkg = getPackageFromConfig(packageConfig, sqlitePackageName);

  final sqlite3Version =
      getPubspecVersion(packageConfigFile, sqlite3Pkg, sqlitePackageName);

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
    print('dependency on package:$packageName is required');
    exit(1);
  }
  return pkg;
}

String getPubspecVersion(
    File packageConfigFile, dynamic package, String packageName) {
  final rootUri = packageConfigFile.uri.resolve(package['rootUri'] ?? '');
  print('Using package:$packageName from ${rootUri.toFilePath()}');

  String pubspec =
      File('${rootUri.toFilePath()}/pubspec.yaml').readAsStringSync();
  Pubspec parsed = Pubspec.parse(pubspec);
  final version = parsed.version?.toString();
  if (version == null) {
    print('${capitalize(packageName)} version not found');
    print('Run `flutter pub get` first.');
    exit(1);
  }
  return version;
}

String capitalize(String s) => s[0].toUpperCase() + s.substring(1);

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
