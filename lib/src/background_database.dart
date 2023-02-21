import 'dart:async';
import 'dart:isolate';

import './sqlite_connection.dart';

import './isolate_completer.dart';
import './mutex.dart';
import './powersync_database.dart';
import './thottle.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;

typedef TxCallback<T> = Future<T> Function(sqlite.Database db);

class SqliteConnectionImpl implements SqliteConnection {
  final SqliteConnectionFactory _factory;

  /// Private to this connection
  final Mutex _connectionMutex = Mutex();

  final Stream<TableUpdate>? updates;
  late final Future<SendPort> sendPortFuture;
  final String? debugName;

  SqliteConnectionImpl(this._factory, {this.updates, this.debugName}) {
    sendPortFuture = _open();
  }

  Future<SendPort> _open() async {
    return await _connectionMutex.lock(() async {
      final portResult = IsolateResult<SendPort>();
      Isolate.spawn(_sqliteConnectionIsolate,
          _SqliteConnectionParams(_factory, portResult.completer),
          debugName: debugName);

      return await portResult.future;
    });
  }

  @override
  Future<sqlite.ResultSet> execute(String sql,
      [List<Object?> parameters = const []]) async {
    return writeTransaction((ctx) async {
      return ctx.execute(sql, parameters);
    });
  }

  @override
  Future<sqlite.ResultSet> getAll(String sql,
      [List<Object?> parameters = const []]) {
    return readTransaction((ctx) async {
      return ctx.getAll(sql, parameters);
    });
  }

  @override
  Future<sqlite.Row> get(String sql, [List<Object?> parameters = const []]) {
    return readTransaction((ctx) async {
      return ctx.get(sql, parameters);
    });
  }

  @override
  Future<sqlite.Row?> getOptional(String sql,
      [List<Object?> parameters = const []]) {
    return readTransaction((ctx) async {
      return ctx.getOptional(sql, parameters);
    });
  }

  /// Run code within the database isolate, in a write (exclusive transaction).
  Future<T> inIsolateWriteTransaction<T>(TxCallback<T> callback) async {
    // TODO: Test properly before making public
    return await writeTransaction((tx) async {
      var sendPort = await sendPortFuture;
      var result = IsolateResult();
      sendPort.send(['tx', result.completer, callback]);
      return await result.future;
    });
  }

  @override
  Future<T> readTransaction<T>(
      Future<T> Function(SqliteReadTransactionContext tx) callback,
      {Duration? lockTimeout}) async {
    // Private lock to synchronize this with other statements on the same connection,
    // to ensure that transactions aren't interleaved.
    return _connectionMutex.lock(() async {
      final ctx = _TransactionContext(await sendPortFuture);
      await ctx.execute('BEGIN');
      try {
        final result = await callback(ctx);
        await ctx.execute('END TRANSACTION');
        return result;
      } catch (e) {
        try {
          await ctx.execute('ROLLBACK');
        } catch (e) {
          // In rare cases, a ROLLBACK may fail.
          // Safe to ignore.
        }
        rethrow;
      } finally {
        ctx.close();
      }
    }, timeout: lockTimeout);
  }

  @override
  Future<T> writeTransaction<T>(
      Future<T> Function(SqliteWriteTransactionContext tx) callback,
      {Duration? lockTimeout}) async {
    // Private lock to synchronize this with other statements on the same connection,
    // to ensure that transactions aren't interleaved.
    final stopWatch = lockTimeout == null ? null : (Stopwatch()..start());
    return _connectionMutex.lock(() async {
      Duration? innerTimeout;
      if (lockTimeout != null && stopWatch != null) {
        innerTimeout = lockTimeout - stopWatch.elapsed;
        stopWatch.stop();
      }
      // DB lock so that only one write happens at a time
      return await _factory.mutex.lock(() async {
        final ctx = _TransactionContext(await sendPortFuture);
        await ctx.execute('BEGIN IMMEDIATE');
        try {
          final result = await callback(ctx);
          await ctx.execute('COMMIT');
          return result;
        } catch (e) {
          try {
            await ctx.execute('ROLLBACK');
          } catch (e) {
            // In rare cases, a ROLLBACK may fail.
            // Safe to ignore.
          }
          rethrow;
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

  @override
  Stream<sqlite.ResultSet> watch(String sql,
      {List<Object?> parameters = const [],
      Duration throttle = const Duration(milliseconds: 30)}) async* {
    assert(updates != null,
        'updates stream must be provided to allow query watching');
    yield await getAll(sql, parameters);
    var throttled = updates!
        .transform(throttleTransformer(const Duration(milliseconds: 30)));
    await for (var _ in throttled) {
      // TODO: Check that that is cancelled properly if the listener is closed.
      // TODO: Only refresh if a relevant table is modified
      yield await getAll(sql, parameters);
    }
  }
}

class _TransactionContext implements SqliteWriteTransactionContext {
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
    return await result.future;
  }

  @override
  Future<sqlite.Row> get(String sql,
      [List<Object?> parameters = const []]) async {
    if (_closed) {
      throw AssertionError('Transaction closed');
    }
    final rows = await getAll(sql, parameters);
    return rows.first;
  }

  @override
  Future<sqlite.Row?> getOptional(String sql,
      [List<Object?> parameters = const []]) async {
    if (_closed) {
      throw AssertionError('Transaction closed');
    }
    final rows = await getAll(sql, parameters);
    return rows.elementAt(0);
  }

  close() {
    _closed = true;
  }
}

void _sqliteConnectionIsolate(_SqliteConnectionParams params) async {
  final db = await params.factory.openRawDatabase();

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

  _SqliteConnectionParams(this.factory, this.portCompleter);
}
