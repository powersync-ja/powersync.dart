import 'dart:io';
import 'package:yaml/yaml.dart';

void main() {
  final pubspecFile = File('packages/powersync/pubspec.yaml');
  final pubspecContent = pubspecFile.readAsStringSync();
  final yaml = loadYaml(pubspecContent);
  final version = yaml['version'];

  final versionFile = File('packages/powersync/lib/src/version.dart');
  versionFile.writeAsStringSync("const String libraryVersion = '$version';\n");

  final packageJson = File('packages/js-assets/package.json');

  String transformPackageJson(String originalContents) {
    final versionLine = RegExp('"version": ".*"');

    return originalContents.replaceFirst(versionLine, '"version": "$version"');
  }

  packageJson
      .writeAsStringSync(transformPackageJson(packageJson.readAsStringSync()));
}
