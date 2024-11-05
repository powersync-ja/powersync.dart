import 'dart:io';

import 'package:interact/interact.dart';
import 'package:yaml/yaml.dart';

void main() {
  final pubspecFile = File('packages/powersync/pubspec.yaml');
  final pubspecContent = pubspecFile.readAsStringSync();
  final yaml = loadYaml(pubspecContent);
  final version = yaml['version'];

  final versionFile = File('packages/powersync/lib/src/version.dart');
  versionFile.writeAsStringSync("const String libraryVersion = '$version';\n");

  // Melos works best when conventional commits are used.
  // We don't strictly follow this pattern which produces unexpected
  // Changelogs that sometimes require manual editing.
  // This script runs before Melos commits the changes.
  // We can allow a user to edit these Changelogs before commit.
  bool confirmed = Confirm(
          prompt:
              'Melos changelogs should be staged for commit. These changes will be committed and tagged. Feel free to edit them before proceeding. Would you like to proceed now?',
          defaultValue: true)
      .interact();

  if (confirmed == false) {
    // Exit with a non-zero code. This will stop the `melos version` process.
    exit(1);
  }
}
