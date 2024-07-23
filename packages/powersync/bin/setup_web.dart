import 'dart:convert';
import 'dart:io';
import 'package:pubspec_parse/pubspec_parse.dart';
// import 'package:args/args.dart';

void main(List<String> arguments) async {
  // Add a flag to enable/disable the download of worker
  // Pass the no_worker argument to disable the download of the worker
  // dart run powersync:setup_web no_worker
  bool downloadWorker = true;
  if (arguments.contains("no_worker")) {
    downloadWorker = false;
  }

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

  final sqlite3Pkg = getPackageFromConfig(packageConfig, sqlitePackageName);

  String sqlite3Version =
      "v${getPubspecVersion(packageConfigFile, sqlite3Pkg, sqlitePackageName)}";

  final httpClient = HttpClient();

  String latestTag = await getLatestTagFromRelease(httpClient);
  String tagVersion = latestTag.split('-')[0];
  if (tagVersion != sqlite3Version) {
    print('Using latest version found on GitHub releases');
    sqlite3Version = latestTag;
  }

  final sqliteUrl =
      'https://github.com/powersync-ja/sqlite3.dart/releases/download/$sqlite3Version/sqlite3.wasm';

  final workerUrl =
      'https://github.com/powersync-ja/powersync.dart/releases/download/v$powersyncVersion/powersync_db.worker.js';

  await downloadFile(httpClient, sqliteUrl, wasmPath);
  if (downloadWorker) await downloadFile(httpClient, workerUrl, workerPath);
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

Future<String> getLatestTagFromRelease(HttpClient httpClient) async {
  var request = await httpClient.getUrl(Uri.parse(
      "https://api.github.com/repos/powersync-ja/sqlite3.dart/releases"));
  var response = await request.close();
  if (response.statusCode == HttpStatus.ok) {
    var res = await response.transform(utf8.decoder).join();
    List<dynamic> jsonObj = json.decode(res);
    return jsonObj[0]['tag_name'];
  } else {
    print('Failed to fetch GitHub releases');
    exit(1);
  }
}

Future<void> downloadFile(
    HttpClient httpClient, String url, String savePath) async {
  print('Downloading: $url');
  var request = await httpClient.getUrl(Uri.parse(url));
  var response = await request.close();
  if (response.statusCode == HttpStatus.ok) {
    var file = File(savePath);
    await response.pipe(file.openWrite());
  } else {
    print(
        'Failed to download file: ${response.statusCode} ${response.reasonPhrase}');
    exit(1);
  }
}
