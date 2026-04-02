import 'dart:io';

/// Replaces the sqlite3 override with sqlite3mc in pubspec.yaml to enable
/// encryption tests.
void main() {
  final file = File('pubspec.yaml');
  final updated = file
      .readAsStringSync()
      .replaceAll('source: sqlite3', 'source: sqlite3mc');
  file.writeAsStringSync(updated);
}
