import 'dart:async';

import './database_interface.dart';

import '../connector.dart';
import '../schema.dart';

// Any imports from sqlite-async must be careful to avoid ffi
import 'package:sqlite_async/definitions.dart';

class PowerSyncDatabase extends AbstractPowerSyncDatabase {
  PowerSyncDatabase({required Schema schema, required String path});

  @override
  Future<void> close() {
    // TODO: implement close
    throw UnimplementedError();
  }

  @override
  // TODO: implement closed
  bool get closed => throw UnimplementedError();

  @override
  connect({required PowerSyncBackendConnector connector}) {
    // TODO: implement connect
    throw UnimplementedError();
  }

  @override
  Future<T> readLock<T>(Future<T> Function(SqliteReadContext tx) callback,
      {String? debugContext, Duration? lockTimeout}) {
    // TODO: implement readLock
    throw UnimplementedError();
  }

  @override
  // TODO: implement schema
  Schema get schema => throw UnimplementedError();

  @override
  Future<T> writeLock<T>(Future<T> Function(SqliteWriteContext tx) callback,
      {String? debugContext, Duration? lockTimeout}) {
    // TODO: implement writeLock
    throw UnimplementedError();
  }
}
