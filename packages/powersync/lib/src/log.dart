import 'package:logging/logging.dart';

// Duplicate from package:flutter/foundation.dart, so we don't need to depend on Flutter
const bool kReleaseMode = bool.fromEnvironment('dart.vm.product');
const bool kProfileMode = bool.fromEnvironment('dart.vm.profile');
const bool kDebugMode = !kReleaseMode && !kProfileMode;

// Implementation note: The loggers here are only initialized if used - it adds
// no overhead when not used in the client app.

final isolateLogger = Logger.detached('PowerSync');

/// Logger that outputs to the console in debug mode, and nothing
/// in release and profile modes.
final Logger autoLogger = _makeAutoLogger();

/// Logger that always outputs debug info to the console.
final Logger debugLogger = _makeDebugLogger();

/// Standard logger. Does not automatically log to the console,
/// use the `Logger.root.onRecord` stream to get log messages.
final Logger attachedLogger = Logger('PowerSync');

Logger _makeDebugLogger() {
  // Use a detached logger to log directly to the console
  final logger = Logger.detached('PowerSync');
  logger.level = Level.FINE;
  logger.onRecord.listen((record) {
    print(
        '[${record.loggerName}] ${record.level.name}: ${record.time}: ${record.message}');

    if (record.error != null) {
      print(record.error);
    }
    if (record.stackTrace != null) {
      print(record.stackTrace);
    }
  });
  return logger;
}

Logger _makeAutoLogger() {
  if (kDebugMode) {
    return _makeDebugLogger();
  } else {
    final logger = Logger.detached('PowerSync');
    logger.level = Level.OFF;
    return logger;
  }
}
