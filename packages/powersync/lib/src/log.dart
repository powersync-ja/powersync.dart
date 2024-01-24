import 'package:logging/logging.dart';

// Duplicate from package:flutter/foundation.dart, so we don't need to depend on Flutter
const bool kReleaseMode = bool.fromEnvironment('dart.vm.product');
const bool kProfileMode = bool.fromEnvironment('dart.vm.profile');
const bool kDebugMode = !kReleaseMode && !kProfileMode;

final isolateLogger = Logger.detached('PowerSync');
