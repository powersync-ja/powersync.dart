import 'dart:io';

import 'package:powersync/src/version.dart';

String? powerSyncUserAgent() {
  var dartVersion = RegExp(r'[\w.]+').stringMatch(Platform.version);
  var dart = 'Dart';
  if (dartVersion != null) {
    dart = "Dart/$dartVersion";
  }
  // Ideally we'd get an OS version, but that's quite complex.
  // Platform.operatingSystemVersion is very verbose.
  return 'PowerSync/$libraryVersion ($dart; ${Platform.operatingSystem})';
}
