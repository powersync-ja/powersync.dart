import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart';
import 'package:tar/tar.dart';
import 'package:path/path.dart' as p;

const repository = 'powersync-ja/agent-skills';
const assetName = 'powersync.tar.gz';

void main() async {
  final client = Client();

  try {
    final downloadUrl = await _findLatestAsset(client);
    print('Downloading skills from $downloadUrl');

    // Note: No authorization header here, the asset is public and the request
    // gets redirected to a different host.
    final response = await client.send(Request('GET', downloadUrl));
    _checkStatus(response, downloadUrl);

    final reader = TarReader(response.stream.transform(gzip.decoder));
    while (await reader.moveNext()) {
      final TarEntry(:header, :contents) = reader.current;
      if (header.typeFlag != .reg) continue;

      // Ignoring the obvious path traversal bug here, we're extracting a
      // trusted source.
      final target = File(
        p.joinAll(['skills', 'powersync-sdk', ...p.url.split(header.name)]),
      );
      final parent = target.parent;
      if (!await parent.exists()) {
        await parent.create(recursive: true);
      }

      await contents.pipe(target.openWrite());
      print('Extracted ${header.name} (${header.size} bytes)');
    }
  } finally {
    client.close();
  }
}

/// Uses the GitHub API to resolve the download URL of [assetName] in the
/// latest release of [repository].
///
/// When running in CI, the `GITHUB_TOKEN` environment variable is forwarded to
/// avoid the low rate limits for unauthenticated requests shared across
/// runners.
Future<Uri> _findLatestAsset(Client client) async {
  final uri = Uri.https('api.github.com', '/repos/$repository/releases/latest');
  final token = Platform.environment['GITHUB_TOKEN'];

  final response = await client.get(
    uri,
    headers: {
      'Accept': 'application/vnd.github+json',
      'X-GitHub-Api-Version': '2026-03-10',
      if (token != null && token.isNotEmpty) 'Authorization': 'Bearer $token',
    },
  );
  _checkStatus(response, uri);

  final release = json.decode(response.body) as Map<String, Object?>;
  print('Latest skills release is ${release['tag_name']}');

  final assets = (release['assets'] as List).cast<Map<String, Object?>>();
  for (final asset in assets) {
    if (asset['name'] == assetName) {
      return Uri.parse(asset['browser_download_url'] as String);
    }
  }

  throw StateError(
    'Release ${release['tag_name']} does not contain $assetName',
  );
}

void _checkStatus(BaseResponse response, Uri uri) {
  if (response.statusCode != 200) {
    throw ClientException(
      'Unexpected status code: ${response.statusCode}',
      uri,
    );
  }
}
