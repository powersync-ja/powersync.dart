import 'dart:io';

/// Replaces the sqlite3 override with sqlite3mc in pubspec.yaml to enable
/// encryption tests.
///
/// Must be run from the root of the repository.
void main() {
  final file = File('pubspec.yaml');
  final updated = file
      .readAsStringSync()
      .replaceFirst('source: sqlite3', 'source: sqlite3mc');
  file.writeAsStringSync(updated);
}
