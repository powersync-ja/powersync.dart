import 'dart:js_interop';

import 'package:sqlite3/wasm.dart';
import 'package:sqlite3_web/sqlite3_web.dart';
import 'package:sqlite_async/sqlite3_web_worker.dart';

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
