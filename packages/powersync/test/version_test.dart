@TestOn('vm')
library;

import 'dart:io';

import 'package:test/test.dart';
import 'package:powersync/src/version.dart';
import 'package:yaml/yaml.dart';

void main() {
  test('libraryVersion matches pubspec version', () {
    final pubspec = loadYamlDocument(File('pubspec.yaml').readAsStringSync());
    final versionInPubspec = (pubspec.contents as YamlMap)['version'] as String;

    expect(libraryVersion, versionInPubspec,
        reason:
            'Version in lib/src/version.dart ($libraryVersion) must match version in pubspec ($versionInPubspec)');
  });
}
