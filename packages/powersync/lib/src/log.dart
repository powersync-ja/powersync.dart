import 'package:logging/logging.dart';
import 'package:powersync/src/log_internal.dart';

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
