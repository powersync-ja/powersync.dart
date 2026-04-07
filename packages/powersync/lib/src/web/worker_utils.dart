import 'dart:js_interop';

import 'package:sqlite3/wasm.dart';
import 'package:sqlite3_web/sqlite3_web.dart';
import 'package:sqlite_async/sqlite3_web_worker.dart';
import 'package:web/web.dart';

final class PowerSyncAsyncSqliteController extends AsyncSqliteController {
  @override
  CommonDatabase openUnderlying(
      WasmSqlite3 sqlite3, String path, String vfs, JSAny? additionalData) {
    final options = additionalData == null
        ? null
        : additionalData as PowerSyncAdditionalOpenOptions;
    if (options != null && options.useMultipleCiphersVfs) {
      vfs = 'multipleciphers-$vfs';
    }

    return sqlite3.open(path, vfs: vfs);
  }

  @override
  Future<JSAny?> handleCustomRequest(
      ClientConnection connection, JSAny? request) {
    throw UnimplementedError();
  }
}

@JS()
@anonymous
extension type PowerSyncAdditionalOpenOptions._(JSObject _)
    implements JSObject {
  external factory PowerSyncAdditionalOpenOptions({
    required bool useMultipleCiphersVfs,
  });

  external bool get useMultipleCiphersVfs;
}

/// A message sent to a PowerSync worker.
///
/// We use a single worker for multiple purposes (hosting databases and
/// coordinating sync across tabs). The database worker protocol is managed by
/// the `sqlite3_web` package, we have `sync_worker_protocol.dart` for the sync
/// worker.
///
/// When we send messages to workers, we wrap them in this structure so that
/// workers know which protocol is used.
@JS()
@anonymous
extension type PowerSyncWorkerMessage._(JSObject _) implements JSObject {
  external bool isForSyncWorker;
  external JSAny? message;

  external factory PowerSyncWorkerMessage({
    required bool isForSyncWorker,
    required JSAny? message,
  });
}

final class PowerSyncWorkerConnector implements WorkerConnector {
  final WorkerConnector _inner;

  PowerSyncWorkerConnector(Uri uri)
      : _inner = WorkerConnector.defaultWorkers(uri);

  @override
  WorkerHandle? spawnDedicatedWorker() {
    return _encapsulateWorker(_inner.spawnDedicatedWorker());
  }

  @override
  WorkerHandle? spawnSharedWorker() {
    return _encapsulateWorker(_inner.spawnSharedWorker());
  }

  /// Wraps an inner [WorkerHandle] to send messages in a
  /// [PowerSyncWorkerMessage] wrapper.
  WorkerHandle? _encapsulateWorker(WorkerHandle? inner) {
    if (inner == null) return null;

    return _PowerSyncWorkerHandle(inner);
  }
}

final class _PowerSyncWorkerHandle implements WorkerHandle {
  final WorkerHandle _inner;

  _PowerSyncWorkerHandle(this._inner);

  @override
  void postMessage(JSAny? msg, JSObject transfer) {
    _inner.postMessage(
        PowerSyncWorkerMessage(isForSyncWorker: false, message: msg), transfer);
  }

  @override
  EventTarget get targetForErrorEvents => _inner.targetForErrorEvents;
}
