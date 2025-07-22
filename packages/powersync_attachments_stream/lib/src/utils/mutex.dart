// lib/src/utils/mutex.dart

import 'dart:async';

class AsyncMutex {
  bool _locked = false;
  final List<Function()> _queue = [];

  Future<T> protect<T>(Future<T> Function() action) async {
    if (_locked) {
      final completer = Completer<T>();
      _queue.add(() async {
        try {
          completer.complete(await action());
        } catch (e, st) {
          completer.completeError(e, st);
        }
      });
      return completer.future;
    } else {
      _locked = true;
      try {
        return await action();
      } finally {
        _locked = false;
        if (_queue.isNotEmpty) {
          final next = _queue.removeAt(0);
          next();
        }
      }
    }
  }
}