import 'dart:async';

import './background_database.dart';
import './powersync_database.dart';
import './sqlite_connection.dart';

class SqliteConnectionPool with SqliteQueries implements SqliteConnection {
  SqliteConnection? _writeConnection;

  final List<SqliteConnectionImpl> _readConnections = [];

  final SqliteConnectionFactory _factory;

  @override
  final Stream<TableUpdate>? updates;

  final int maxReaders;

  final String? debugName;

  SqliteConnectionPool(this._factory,
      {this.updates,
      this.maxReaders = 5,
      SqliteConnection? writeConnection,
      this.debugName})
      : _writeConnection = writeConnection;

  @override
  Future<T> readTransaction<T>(
      Future<T> Function(SqliteReadTransactionContext tx) callback,
      {Duration? lockTimeout}) async {
    _expandPool();

    bool haveLock = false;
    var completer = Completer<T>();

    var futures = _readConnections.map((connection) async {
      try {
        return await connection.lock(() async {
          if (haveLock) {
            // Alreay have a different lock - release this one.
            return false;
          }
          haveLock = true;

          var future = connection.readTransactionInLock(callback);
          completer.complete(future);

          // We have to wait for the future to complete before we can release the
          // lock.
          try {
            await future;
          } catch (_) {
            // Ignore
          }

          return true;
        }, timeout: lockTimeout);
      } on TimeoutException {
        return false;
      }
    });

    final stream = Stream<bool>.fromFutures(futures);
    var gotAny = await stream.any((element) => element);

    if (!gotAny) {
      // All TimeoutExceptions
      throw TimeoutException('Failed to get a read connection', lockTimeout);
    }

    try {
      return await completer.future;
    } catch (e) {
      // throw e;
      rethrow;
    }
  }

  @override
  Future<T> writeTransaction<T>(
      Future<T> Function(SqliteWriteTransactionContext tx) callback,
      {Duration? lockTimeout}) {
    _writeConnection ??= _factory.openConnection(
        debugName: debugName != null ? '$debugName-writer' : null);
    return _writeConnection!
        .writeTransaction(callback, lockTimeout: lockTimeout);
  }

  void _expandPool() {
    if (_readConnections.length >= maxReaders) {
      return;
    }
    bool hasCapacity = _readConnections.any((connection) => !connection.locked);
    if (!hasCapacity) {
      var name = debugName == null
          ? null
          : '$debugName-${_readConnections.length + 1}';
      _readConnections.add(_factory.openConnection(
          updates: updates,
          debugName: name,
          readOnly: true) as SqliteConnectionImpl);
    }
  }
}
