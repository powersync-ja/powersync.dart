import 'package:powersync_core/src/version.dart';

String powerSyncUserAgent() {
  return 'powersync-dart-core/$libraryVersion Dart (flutter-web)';
}

Map<String, String> userAgentHeaders() {
  var ua = powerSyncUserAgent();
  // Chrome doesn't allow overriding the user agent.
  // Instead, we send an additional x-user-agent header.
  return {'X-User-Agent': ua};
}
