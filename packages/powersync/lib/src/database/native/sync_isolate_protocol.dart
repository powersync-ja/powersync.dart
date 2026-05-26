import 'dart:async';
import 'dart:isolate';

import 'package:logging/logging.dart';
import 'package:sqlite_async/sqlite_async.dart';

import '../../connector.dart';
import '../../isolate_completer.dart';
import '../../sync/streaming_sync.dart' show SubscribedStream;
import '../../sync/sync_status.dart';

// A (type, payload) pair sent between main app and sync isolate
typedef SyncIsolateToClientMessage = (SyncIsolateToClientMessageType, Object?);
typedef ClientToSyncIsolateMessage = (ClientToSyncIsolateMessageType, Object?);

/// Type of messages sent from the sync isolate to the main app.
enum SyncIsolateToClientMessageType {
  /// Invokes [PowerSyncBackendConnector.getCredentialsCached], payload is a
  /// [PortCompleter] expecting the [PowerSyncCredentials].
  getCredentialsCached,

  /// Prefetch credentials, payload is a ([PortCompleter], `bool invalidate`)
  /// pair.
  prefetchCredentials,

  /// The sync isolate is ready to take commands, payload is a
  /// [SyncIsolatePort].
  init,

  /// Upload the CRUD queue, payload is a [PortCompleter].
  uploadCrud,

  /// The sync status has changed, payload is a [SyncStatus].
  status,

  /// Incoming log message, payload is a [LogRecord].
  log,

  /// The sync isolate wants to acquire a mutex, payload is a (`String name`,
  /// `int requestId`) pair.
  mutexAcquire,

  /// The sync isolate wants to release a mutex, payload is an [int] request id.
  mutexRelease;
}

enum ClientToSyncIsolateMessageType {
  /// Active Sync Stream subscriptions referenced in the app have changed,
  /// payload is a list of [SubscribedStream]s.
  changedSubscriptions,

  /// The sync isolate should start shutting down.
  close,

  /// A completed [SyncIsolateToClientMessageType.mutexAcquire] call, payload is
  /// the request id being completed.
  mutexGranted,
}

/// Typed client-side view over a [SendPort] used to send messages to a sync
/// isolate.
extension type SyncIsolatePort(SendPort port) {
  void send(ClientToSyncIsolateMessageType type, [Object? payload]) {
    port.send((type, payload));
  }

  void sendChangedSubscriptions(List<SubscribedStream> streams) {
    send(ClientToSyncIsolateMessageType.changedSubscriptions, streams);
  }

  void sendClose() {
    send(ClientToSyncIsolateMessageType.close);
  }

  void sendMutexGranted(int requestId) {
    send(ClientToSyncIsolateMessageType.mutexGranted, requestId);
  }
}

/// Sync isolate view over a [SendPort] used to send messages to a client
/// isolate managing the sync process.
extension type SyncClientPort(SendPort port) {
  void send(SyncIsolateToClientMessageType type, [Object? payload]) {
    port.send((type, payload));
  }

  void sendInit(SendPort port) {
    send(SyncIsolateToClientMessageType.init, port);
  }

  void sendGetCredentialsCached(
      PortCompleter<PowerSyncCredentials?> completer) {
    send(SyncIsolateToClientMessageType.getCredentialsCached, completer);
  }

  void sendPrefetchCredentials(
      PortCompleter<PowerSyncCredentials?> completer, bool invalidate) {
    send(SyncIsolateToClientMessageType.prefetchCredentials,
        (completer, invalidate));
  }

  void sendUploadCrud(PortCompleter<void> completer) {
    send(SyncIsolateToClientMessageType.uploadCrud, completer);
  }

  void sendLog(LogRecord record) {
    send(SyncIsolateToClientMessageType.log, record);
  }

  void sendStatus(SyncStatus event) {
    send(SyncIsolateToClientMessageType.status, event);
  }

  void sendAcquireMutex(String name, int request) {
    send(SyncIsolateToClientMessageType.mutexAcquire, (name, request));
  }

  void sendReleaseMutex(int requestId) {
    send(SyncIsolateToClientMessageType.mutexRelease, requestId);
  }
}

/// Allows the sync isolate to acquire [Mutex]es from its parent.
///
/// This is only used between the main and the sync isolate, and integrates into
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

  void acquireRequest(SyncIsolatePort sendPort, String name, int requestId) {
    assert(!_didExit);
    final mutex = _mutexes[name]!;
    mutex.lock(() {
      if (_didExit) {
        return Future<void>.value();
      }

      final completer = Completer<void>.sync();
      _held[requestId] = completer;
      sendPort.sendMutexGranted(requestId);
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
  final SyncClientPort sendPort;
  int _nextRequestId = 0;
  final Map<int, Completer<void>> _inflightRequests = {};

  RemoteMutexes(this.sendPort);

  Future<GrantedRemoteMutex> acquire(String name) async {
    final id = _nextRequestId++;
    final completer = _inflightRequests[id] = Completer.sync();
    sendPort.sendAcquireMutex(name, id);

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
    _mutexes.sendPort.sendReleaseMutex(_requestId);
  }
}
