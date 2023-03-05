import 'dart:async';
import 'dart:isolate';

import 'package:powersync/src/database_utils.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;

import './isolate_completer.dart';
import './mutex.dart';
import './powersync_database.dart';
import './sqlite_connection.dart';
import './throttle.dart';

typedef TxCallback<T> = Future<T> Function(sqlite.Database db);

class SqliteConnectionImpl with SqliteQueries implements SqliteConnection {
  final SqliteConnectionFactory _factory;

  /// Private to this connection
  final SimpleMutex _connectionMutex = SimpleMutex();

  @override
  final Stream<TableUpdate>? updates;
  late final Future<SendPort> sendPortFuture;
  final String? debugName;
  final bool readOnly;

  SqliteConnectionImpl(this._factory,
      {this.updates, this.debugName, this.readOnly = false}) {
    sendPortFuture = _open();
  }

  Future<void> get ready {
    return sendPortFuture;
  }

  Future<SendPort> _open() async {
    return await _connectionMutex.lock(() async {
      final portResult = IsolateResult<SendPort>();
      Isolate.spawn(
          _sqliteConnectionIsolate,
          _SqliteConnectionParams(_factory, portResult.completer,
              readOnly: readOnly),
          debugName: debugName);

      return await portResult.future;
    });
  }

  bool get locked {
    return _connectionMutex.locked;
  }

  /// For internal use only
  Future<T> lock<T>(Future<T> Function() callback, {Duration? timeout}) async {
    return _connectionMutex.lock(callback, timeout: timeout);
  }

  @override
  Future<T> readLock<T>(Future<T> Function(SqliteReadContext tx) callback,
      {Duration? lockTimeout}) async {
    // Private lock to synchronize this with other statements on the same connection,
    // to ensure that transactions aren't interleaved.
    return _connectionMutex.lock(() async {
      final ctx = _TransactionContext(await sendPortFuture);
      try {
        return await callback(ctx);
      } finally {
        ctx.close();
      }
    }, timeout: lockTimeout);
  }

  @override
  Future<T> writeLock<T>(Future<T> Function(SqliteWriteContext tx) callback,
      {Duration? lockTimeout}) async {
    final stopWatch = lockTimeout == null ? null : (Stopwatch()..start());
    // Private lock to synchronize this with other statements on the same connection,
    // to ensure that transactions aren't interleaved.
    return _connectionMutex.lock(() async {
      Duration? innerTimeout;
      if (lockTimeout != null && stopWatch != null) {
        innerTimeout = lockTimeout - stopWatch.elapsed;
        stopWatch.stop();
      }
      // DB lock so that only one write happens at a time
      return await _factory.mutex.lock(() async {
        final ctx = _TransactionContext(await sendPortFuture);
        try {
          return await callback(ctx);
        } finally {
          ctx.close();
        }
      }, timeout: innerTimeout).catchError((error, stackTrace) {
        if (error is TimeoutException) {
          return Future<T>.error(TimeoutException(
              'Failed to acquire global write lock', lockTimeout));
        }
        return Future<T>.error(error, stackTrace);
      });
    }, timeout: lockTimeout);
  }
}

class _TransactionContext implements SqliteWriteContext {
  final SendPort _sendPort;
  bool _closed = false;

  _TransactionContext(this._sendPort);

  @override
  Future<sqlite.ResultSet> execute(String sql,
      [List<Object?> parameters = const []]) async {
    if (_closed) {
      throw AssertionError('Transaction closed');
    }
    var result = IsolateResult<sqlite.ResultSet>();
    _sendPort.send(['select', result.completer, sql, parameters, 'readwrite']);
    return await result.future;
  }

  @override
  Future<sqlite.ResultSet> getAll(String sql,
      [List<Object?> parameters = const []]) async {
    if (_closed) {
      throw AssertionError('Transaction closed');
    }
    var result = IsolateResult<sqlite.ResultSet>();
    _sendPort.send(['select', result.completer, sql, parameters, 'readonly']);
    try {
      return await result.future;
    } on sqlite.SqliteException catch (e) {
      if (e.resultCode == 8) {
        // SQLITE_READONLY
        throw sqlite.SqliteException(
            e.extendedResultCode,
            'attempt to write in a read-only transaction',
            null,
            e.causingStatement);
      }
      rethrow;
    }
  }

  @override
  Future<T> computeWithDatabase<T>(
      Future<T> Function(sqlite.Database db) compute) async {
    var result = IsolateResult();
    _sendPort.send(['tx', result.completer, compute]);
    return await result.future;
  }

  @override
  Future<sqlite.Row> get(String sql,
      [List<Object?> parameters = const []]) async {
    final rows = await getAll(sql, parameters);
    return rows.first;
  }

  @override
  Future<sqlite.Row?> getOptional(String sql,
      [List<Object?> parameters = const []]) async {
    final rows = await getAll(sql, parameters);
    return rows.elementAt(0);
  }

  close() {
    _closed = true;
  }

  @override
  Future<void> executeBatch(String sql, List<List<Object?>> parameterSets) {
    return computeWithDatabase((db) async {
      final statement = db.prepare(sql);
      try {
        for (var parameters in parameterSets) {
          statement.execute(parameters);
        }
      } finally {
        statement.dispose();
      }
    });
  }
}

void _sqliteConnectionIsolate(_SqliteConnectionParams params) async {
  final db = await params.factory.openRawDatabase(readOnly: params.readOnly);

  final commandPort = ReceivePort();
  params.portCompleter.complete(commandPort.sendPort);

  commandPort.listen((data) async {
    if (data is List) {
      String action = data[0];
      PortCompleter completer = data[1];
      if (action == 'select') {
        await completer.handle(() async {
          String query = data[2];
          List<Object?> args = data[3];
          var results = db.select(query, args);
          return results;
        }, ignoreStackTrace: true);
      } else if (action == 'tx') {
        await completer.handle(() async {
          TxCallback cb = data[2];
          var result = await cb(db);
          return result;
        });
      }
    }
  });
}

class _SqliteConnectionParams {
  SqliteConnectionFactory factory;
  PortCompleter<SendPort> portCompleter;
  bool readOnly;

  _SqliteConnectionParams(this.factory, this.portCompleter,
      {required this.readOnly});
}
