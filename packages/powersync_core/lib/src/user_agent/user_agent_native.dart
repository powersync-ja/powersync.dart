import 'dart:io';

import 'package:powersync_core/src/version.dart';

String powerSyncUserAgent() {
  var dartVersion = RegExp(r'[\w.]+').stringMatch(Platform.version);
  var dart = 'Dart';
  if (dartVersion != null) {
    dart = "Dart/$dartVersion";
  }
  // Ideally we'd get an OS version as well, but that's a little complex.
  // Platform.operatingSystemVersion is very verbose.
  return 'powersync-dart/$libraryVersion $dart ${Platform.operatingSystem}';
}

Map<String, String> userAgentHeaders() {
  return {'User-Agent': powerSyncUserAgent()};
}
