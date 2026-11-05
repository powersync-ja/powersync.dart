@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';
import 'package:powersync/src/version.dart';
import 'package:yaml/yaml.dart';

void main() {
  // Note: If these tests fail after updating pubspec.yaml, running
  // dart tool/update_version.dart in the workspace root fixes them.

  test('libraryVersion matches pubspec version', () {
    final pubspec = loadYamlDocument(File('pubspec.yaml').readAsStringSync());
    final versionInPubspec = (pubspec.contents as YamlMap)['version'] as String;

    expect(
      libraryVersion,
      versionInPubspec,
      reason:
          'Version in lib/src/version.dart ($libraryVersion) must match version in pubspec ($versionInPubspec)',
    );
  });

  test('npm version matches library version', () {
    // We publish an npm companion package containing our sqlite3.wasm and web
    // worker assets. The Kotlin SDK depends on these for web support. Each
    // version is published to both pub.dev and npmjs.com, so versions need to
    // stay in sync.
    final {'version': version} =
        json.decode(File('../js-assets/package.json').readAsStringSync())
            as Map<String, Object?>;

    expect(
      version,
      libraryVersion,
      reason:
          'Version in lib/src/version.dart ($libraryVersion) must match version in package.json ($version)',
    );
  });
}
