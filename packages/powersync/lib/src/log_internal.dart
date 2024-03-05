import 'package:logging/logging.dart';

// Duplicate from package:flutter/foundation.dart, so we don't need to depend on Flutter
const bool kReleaseMode = bool.fromEnvironment('dart.vm.product');
const bool kProfileMode = bool.fromEnvironment('dart.vm.profile');
const bool kIsWeb = bool.fromEnvironment('dart.library.js_util');
const bool kDebugMode = !kReleaseMode && !kProfileMode;

// Implementation note: The loggers here are only initialized if used - it adds
// no overhead when not used in the client app.

final isolateLogger = Logger.detached('PowerSync');
