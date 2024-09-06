import 'package:powersync/src/version.dart';

String powerSyncUserAgent() {
  return 'powersync-dart/$libraryVersion (flutter-web)';
}

Map<String, String> userAgentHeaders() {
  var ua = powerSyncUserAgent();
  // Chrome doesn't allow overriding the user agent.
  // Instead, we send an additional x-user-agent header.
  return {'X-User-Agent': ua};
}
