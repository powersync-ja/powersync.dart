import 'dart:io';
import 'package:yaml/yaml.dart';

void main() {
  final pubspecFile = File('packages/powersync/pubspec.yaml');
  final pubspecContent = pubspecFile.readAsStringSync();
  final yaml = loadYaml(pubspecContent);
  final version = yaml['version'];

  final versionFile = File('packages/powersync_core/lib/src/version.dart');
  versionFile.writeAsStringSync("const String libraryVersion = '$version';\n");
}
