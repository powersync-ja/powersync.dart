import 'dart:convert';
import 'dart:io';

import 'package:collection/collection.dart';
import 'package:powersync_core/src/setup/native.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;

Future<void> main() async {
  final client = http.Client();
  final sourceFile = File('lib/src/setup/native.dart');
  final originalContents = await sourceFile.readAsString();

  final assets = await _fetchReleaseAssets(client, releaseVersion);
  final entries = <(String, String)>[];

  for (final asset in assets) {
    final name = asset['name'] as String;
    if (p.url.extension(name) case '.dll' || '.dylib' || '.so') {
      final [_, hash] = (asset['digest'] as String).split(':');

      entries.add((name, hash));
    }
  }

  entries.sortBy((e) => e.$1);
  const startMarker = '  // start of generated hashes';
  const endMarker = '  // end of generated hashes';

  final newContents = StringBuffer();
  newContents
    ..write(
        originalContents.substring(0, originalContents.indexOf(startMarker)))
    ..writeln(startMarker);
  for (final (fileName, digest) in entries) {
    newContents
      ..writeln("  '$fileName':")
      ..writeln("      '$digest',");
  }

  newContents
      .write(originalContents.substring(originalContents.indexOf(endMarker)));

  client.close();
  await sourceFile.writeAsString(newContents.toString());
}

Future<List<Map<String, dynamic>>> _fetchReleaseAssets(
    http.Client client, String tag) async {
  final uri = Uri.parse(
      'https://api.github.com/repos/powersync-ja/powersync-sqlite-core/releases/tags/$tag');
  final response = await client.get(uri, headers: {
    'Accept': 'application/vnd.github+json',
    'User-Agent': 'powersync-dart-tool',
  });

  if (response.statusCode != 200) {
    throw Exception(
        'GitHub API error ${response.statusCode} fetching release $tag');
  }

  final release = json.decode(response.body) as Map<String, dynamic>;
  return (release['assets'] as List).cast<Map<String, dynamic>>();
}
