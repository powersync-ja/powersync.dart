import 'dart:async';

import 'package:sqlite_async/sqlite3_common.dart';
import 'package:sqlite_async/src/sqlite_open_factory.dart';
import 'package:sqlite3/wasm.dart';
import '../open_factory_interface.dart' as open_factory;

class PowerSyncOpenFactory extends open_factory.AbstractPowerSyncOpenFactory {
  PowerSyncOpenFactory({required super.path});

  void enableExtension() {
    // No op for web
  }

  void setupFunctions(CommonDatabase db) {
    // No op for web
  }

  @override
  FutureOr<CommonDatabase> open(SqliteOpenOptions options) async {
    // todo static init
    final sqlite =
        await WasmSqlite3.loadFromUrl(Uri.parse('sqlite3.debug.wasm'));
    sqlite.registerVirtualFileSystem(
      await IndexedDbFileSystem.open(dbName: 'powersync'),
      makeDefault: true,
    );

    return sqlite.open(path);
  }
}
