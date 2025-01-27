import 'dart:convert';
import 'dart:io';
import 'package:collection/collection.dart';
import 'package:pub_semver/pub_semver.dart';
import 'package:pubspec_parse/pubspec_parse.dart';
import 'package:args/args.dart';

Future<void> downloadWebAssets(List<String> arguments,
    {bool encryption = false}) async {
  var parser = ArgParser();
  // Add a flag to enable/disable the download of worker (defaults to true)
  // Pass the --no-worker argument to disable the download of the worker
  // dart run powersync:setup_web --no-worker
  parser.addFlag('worker', defaultsTo: true);
  // Add a option to specify the output directory (defaults to web)
  // Pass the --output-dir argument to specify the output directory
  // dart run powersync:setup_web --output-dir assets
  parser.addOption('output-dir', abbr: 'o', defaultsTo: 'web');
  var results = parser.parse(arguments);
  bool downloadWorker = results.flag('worker');
  String outputDir = results.option('output-dir')!;

  final root = Directory.current.uri;
  print('Project root: ${root.toFilePath()}');

  final wasmFileName = encryption ? 'sqlite3mc.wasm' : 'sqlite3.wasm';
  final wasmPath = '${root.toFilePath()}$outputDir/$wasmFileName';

  final workerPath = '${root.toFilePath()}$outputDir/powersync_db.worker.js';
  final syncWorkerPath =
      '${root.toFilePath()}$outputDir/powersync_sync.worker.js';

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

  try {
    final httpClient = HttpClient();

    final powersyncPackageName = 'powersync';

    if (downloadWorker) {
      final powersyncPkg =
          getPackageFromConfig(packageConfig, powersyncPackageName);

      final powersyncVersion = getPubspecVersion(
          packageConfigFile, powersyncPkg, powersyncPackageName);

      final workerUrl =
          'https://github.com/powersync-ja/powersync.dart/releases/download/powersync-v$powersyncVersion/powersync_db.worker.js';

      final syncWorkerUrl =
          'https://github.com/powersync-ja/powersync.dart/releases/download/powersync-v$powersyncVersion/powersync_sync.worker.js';

      await downloadFile(httpClient, workerUrl, workerPath);
      await downloadFile(httpClient, syncWorkerUrl, syncWorkerPath);
    }

    final sqlitePackageName = 'sqlite3';

    final sqlite3Pkg = getPackageFromConfig(packageConfig, sqlitePackageName);

    String sqlite3Version =
        "v${getPubspecVersion(packageConfigFile, sqlite3Pkg, sqlitePackageName)}";

    List<String> tags = await getLatestTagsFromRelease(httpClient);
    String? matchTag = tags.firstWhereOrNull((element) =>
        element.contains(sqlite3Version) && coreVersionIsInRange(element));
    if (matchTag != null) {
      sqlite3Version = matchTag;
    } else {
      throw Exception(
          """No compatible powersync core version found for sqlite3 version $sqlite3Version
          Latest supported sqlite3 versions: ${tags.take(3).map((tag) => tag.split('-')[0]).join(', ')}.
          You can view the full list of releases at https://github.com/powersync-ja/sqlite3.dart/releases""");
    }

    final sqliteUrl =
        'https://github.com/powersync-ja/sqlite3.dart/releases/download/$sqlite3Version/$wasmFileName';

    await downloadFile(httpClient, sqliteUrl, wasmPath);
  } catch (e) {
    print(e);
    exit(1);
  }
}

bool coreVersionIsInRange(String tag) {
  // Sets the range of powersync core version that is compatible with the sqlite3 version
  // We're a little more selective in the versions chosen here than the range
  // we're compatible with.
  VersionConstraint constraint = VersionConstraint.parse('>=0.3.0 <0.4.0');
  List<String> parts = tag.split('-');
  String powersyncPart = parts[1];

  List<String> versionParts = powersyncPart.split('.');
  String extractedVersion =
      versionParts.sublist(versionParts.length - 3).join('.');
  final coreVersion = Version.parse(extractedVersion);
  if (constraint.allows(coreVersion)) {
    return true;
  }
  return false;
}

dynamic getPackageFromConfig(dynamic packageConfig, String packageName) {
  final pkg = (packageConfig['packages'] ?? []).firstWhere(
    (e) => e['name'] == packageName,
    orElse: () => null,
  );
  if (pkg == null) {
    throw Exception('Dependency on package:$packageName is required');
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
    throw Exception(
        "${capitalize(packageName)} version not found. Run `flutter pub get` first.");
  }
  return version;
}

String capitalize(String s) => s[0].toUpperCase() + s.substring(1);

Future<List<String>> getLatestTagsFromRelease(HttpClient httpClient) async {
  var request = await httpClient.getUrl(Uri.parse(
      "https://api.github.com/repos/powersync-ja/sqlite3.dart/releases"));
  var response = await request.close();
  if (response.statusCode == HttpStatus.ok) {
    var res = await response.transform(utf8.decoder).join();
    List<dynamic> jsonObj = json.decode(res);
    List<String> tags = [];
    for (dynamic obj in jsonObj) {
      final tagName = obj['tag_name'] as String;
      if (!tagName.contains("-powersync")) continue;
      tags.add(tagName);
    }
    return tags;
  } else {
    throw Exception("Failed to fetch GitHub releases and tags");
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
    throw Exception(
        'Failed to download file: ${response.statusCode} ${response.reasonPhrase}');
  }
}
