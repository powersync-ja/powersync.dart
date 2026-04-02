import 'dart:async';
import 'dart:isolate';

import 'package:sqlite_async/sqlite_async.dart';

/// Allows a child isolate to acquire [Mutex]es from a parent isolate.
///
/// This is only used between teh main and the sync isolate, and integrates into
/// the existing communication channel set up between those.
///
/// The protocol is:
///
/// 1. The child isolate sends a `[mutex:acquire, $name, $requestId]` message.
/// 2. Once granted, the parent isolate responds with `[mutex:granted, $requestId]`.
/// 3. To exit a critical section, the child isolate sends `[mutex:release, $requestId]`.
///
/// Once the child isolate exists, the parent isolate returns all held mutexes.
final class MutexServer {
  final Map<String, Mutex> _mutexes;
  final Map<int, Completer<void>> _held = {};
  var _didExit = false;

  MutexServer(this._mutexes);

  void acquireRequest(SendPort sendPort, String name, int requestId) {
    assert(!_didExit);
    final mutex = _mutexes[name]!;
    mutex.lock(() {
      if (_didExit) {
        return Future<void>.value();
      }

      final completer = Completer<void>.sync();
      _held[requestId] = completer;
      sendPort.send(['mutex:granted', requestId]);
      return completer.future;
    });
  }

  void releaseRequest(int requestId) {
    _held.remove(requestId)?.complete();
  }

  void handleChildIsolateExit() {
    _didExit = true;
    for (final pending in _held.values) {
      pending.complete();
    }
    _held.clear();
  }
}

final class RemoteMutexes {
  final SendPort sendPort;
  int _nextRequestId = 0;
  final Map<int, Completer<void>> _inflightRequests = {};

  RemoteMutexes(this.sendPort);

  Future<GrantedRemoteMutex> acquire(String name) async {
    final id = _nextRequestId++;
    final completer = _inflightRequests[id] = Completer.sync();
    sendPort.send(['mutex:acquire', name, id]);

    await completer.future;
    return GrantedRemoteMutex._(this, id);
  }

  /// Signal that a `mutex:grant` message has been received.
  void markGranted(int requestId) {
    _inflightRequests.remove(requestId)!.complete();
  }

  Mutex mutex(String name) {
    return _RemoteMutex(this, name);
  }
}

final class _RemoteMutex implements Mutex {
  final RemoteMutexes _server;
  final String name;

  _RemoteMutex(this._server, this.name);

  @override
  Future<T> lock<T>(Future<T> Function() callback,
      {Future<void>? abortTrigger}) async {
    final grant = await _server.acquire(name);
    try {
      return await callback();
    } finally {
      grant.release();
    }
  }
}

final class GrantedRemoteMutex {
  final RemoteMutexes _mutexes;
  final int _requestId;

  GrantedRemoteMutex._(this._mutexes, this._requestId);

  void release() {
    _mutexes.sendPort.send(['mutex:release', _requestId]);
  }
}
