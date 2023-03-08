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
  Future<T> readLock<T>(Future<T> Function(SqliteReadContext tx) callback,
      {Duration? lockTimeout}) async {
    await _expandPool();

    bool haveLock = false;
    var completer = Completer<T>();

    var futures = _readConnections.map((connection) async {
      try {
        return await connection.readLock((ctx) async {
          if (haveLock) {
            // Already have a different lock - release this one.
            return false;
          }
          haveLock = true;

          var future = callback(ctx);
          completer.complete(future);

          // We have to wait for the future to complete before we can release the
          // lock.
          try {
            await future;
          } catch (_) {
            // Ignore
          }

          return true;
        }, lockTimeout: lockTimeout);
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
  Future<T> writeLock<T>(Future<T> Function(SqliteWriteContext tx) callback,
      {Duration? lockTimeout}) {
    _writeConnection ??= _factory.openConnection(
        debugName: debugName != null ? '$debugName-writer' : null);
    return _writeConnection!.writeLock(callback, lockTimeout: lockTimeout);
  }

  Future<void> _expandPool() async {
    if (_readConnections.length >= maxReaders) {
      return;
    }
    bool hasCapacity = _readConnections.any((connection) => !connection.locked);
    if (!hasCapacity) {
      var name = debugName == null
          ? null
          : '$debugName-${_readConnections.length + 1}';
      var connection = _factory.openConnection(
          updates: updates,
          debugName: name,
          readOnly: true) as SqliteConnectionImpl;
      _readConnections.add(connection);

      // Edge case:
      // If we don't await here, there is a chance that a different connection
      // is used for the transaction, and that it finishes and deletes the database
      // while this one is still opening. This is specifically triggered in tests.
      // To avoid that, we wait for the connection to be ready.
      await connection.ready;
    }
  }
}
