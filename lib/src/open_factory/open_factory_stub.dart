import 'dart:async';

import 'package:sqlite_async/sqlite3_common.dart';
import 'package:sqlite_async/sqlite_async.dart';
import 'package:sqlite_async/src/sqlite_open_factory.dart';
import './open_factory_interface.dart' as open_factory;

class PowerSyncOpenFactory extends open_factory.PowerSyncOpenFactory {
  PowerSyncOpenFactory(String path, SqliteOptions? options);

  void enableExtension() {
    throw UnimplementedError();
  }

  void setupFunctions(CommonDatabase db) {
    throw UnimplementedError();
  }

  @override
  FutureOr<CommonDatabase> open(SqliteOpenOptions options) {
    // TODO: implement open
    throw UnimplementedError();
  }
}
