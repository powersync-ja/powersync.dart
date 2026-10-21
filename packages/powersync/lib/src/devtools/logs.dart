import 'dart:collection';

import 'package:logging/logging.dart';

/// Utilities to forward log lines to DevTools.
///
/// This replaces the logger on a PowerSync database with [newSource], a
/// detached logger recording all log events. Log events are also forwarded to
/// the logger originally configured on the database.
final class LogStore {
  final Logger newSource = Logger.detached('PowerSync DevTools forwarder');
  final _buffer = ListQueue<Object>(_logRingBufferSize);

  LogStore() {
    newSource.level = Level.ALL;
  }

  void observe(Logger existing) {
    newSource.onRecord.listen((record) {
      _addToBuffer(record);

      existing.log(
        record.level,
        record.message,
        record.error,
        record.stackTrace,
        record.zone,
      );
    });
  }

  void _addToBuffer(LogRecord record) {
    if (_buffer.length == _logRingBufferSize) {
      _buffer.removeFirst();
    }
    _buffer.addLast(serializeLog(record));
  }

  List<Object> copyBuffer() {
    return _buffer.toList();
  }

  static const _logRingBufferSize = 64;
}

/// Serializes a Dart log record into the format used by the JS devtools
/// integration (https://github.com/powersync-ja/powersync-js/blob/582babec1e676d9c4b90bd8d5311ec32055d68fa/tools/diagnostics-core/src/shapes.ts#L103-L111).
Object serializeLog(LogRecord record) {
  return {
    'timestamp': record.time.millisecondsSinceEpoch,
    'level': switch (record.level) {
      <= Level.FINER => 'trace',
      <= Level.FINE => 'debug',
      <= Level.INFO => 'info',
      <= Level.WARNING => 'warning',
      _ => 'error',
    },
    'message': record.message,
    if (record.error case final error?)
      'args': [Error.safeToString(error), ?record.stackTrace?.toString()],
  };
}
