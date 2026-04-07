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

/// A message sent to a shared PowerSync worker.
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
extension type SharedWorkerMessage._(JSObject _) implements JSObject {
  external bool isForSyncWorker;
  external JSAny? message;

  external factory SharedWorkerMessage({
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
    // We don't need to wrap this, dedicated workers are only used for databases
    // and we don't send SharedWorkerMessages to those.
    return _inner.spawnDedicatedWorker();
  }

  @override
  WorkerHandle? spawnSharedWorker() {
    return switch (_inner.spawnSharedWorker()) {
      null => null,
      final worker => _SharedWorkerHandle(worker),
    };
  }
}

final class _SharedWorkerHandle implements WorkerHandle {
  final WorkerHandle _inner;

  _SharedWorkerHandle(this._inner);

  @override
  void postMessage(JSAny? msg, JSObject transfer) {
    _inner.postMessage(
        SharedWorkerMessage(isForSyncWorker: false, message: msg), transfer);
  }

  @override
  EventTarget get targetForErrorEvents => _inner.targetForErrorEvents;
}
