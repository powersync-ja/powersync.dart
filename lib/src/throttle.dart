import 'dart:async';

import 'package:powersync/powersync.dart';
import 'package:powersync/src/schema_logic.dart';

StreamTransformer<T, T> throttleTransformer<T>(Duration timeout) {
  Timer? timer;
  T? lastData;

  return StreamTransformer<T, T>.fromHandlers(handleData: (data, sink) {
    lastData = data;
    timer ??= Timer(timeout, () {
      sink.add(lastData as T);
      timer = null;
      lastData = null;
    });
  });
}

/// Given a broadcast stream, return a singular throttled stream that is throttled.
/// This immediately starts listening.
///
/// Behaviour:
///   If there was no event in "timeout", and one comes in, it is pushed immediately.
///   Otherwise, we wait until the timeout is over.
Stream<T> throttleStream<T>(Stream<T> input, Duration timeout,
    {bool throttleFirst = false}) async* {
  var nextPing = Completer<void>();
  T? lastData;

  var listener = input.listen((data) {
    lastData = data;
    if (!nextPing.isCompleted) {
      nextPing.complete();
    }
  });

  try {
    if (throttleFirst) {
      await Future.delayed(timeout);
    }
    while (true) {
      // If a value is available now, we'll use it immediately.
      // If not, this waits for it.
      await nextPing.future;
      // Capture any new values coming in while we wait.
      nextPing = Completer<void>();
      yield lastData as T;
      // Wait a minimum of this duration between tasks
      await Future.delayed(timeout);
    }
  } finally {
    listener.cancel();
  }
}

/// Filter an update stream by specific tables
StreamTransformer<TableUpdate, TableUpdate> filterTablesTransformer(
    Iterable<String> tables) {
  Set<String> normalized = {};
  for (var table in tables) {
    String? friendlyName = friendlyTableName(table);
    if (friendlyName != null) {
      normalized.add(friendlyName.toLowerCase());
    } else {
      normalized.add(table.toLowerCase());
    }
  }
  return StreamTransformer<TableUpdate, TableUpdate>.fromHandlers(
      handleData: (data, sink) {
    if (normalized.contains(data.name.toLowerCase())) {
      sink.add(data);
    }
  });
}
