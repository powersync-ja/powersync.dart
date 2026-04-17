import 'dart:async';
import 'dart:convert';

import 'package:powersync/powersync.dart';
import 'package:sqlite3/common.dart';
import 'package:sqlite_async/sqlite_async.dart';
import 'package:vm_service/vm_service.dart';

// ignore: implementation_imports
import 'package:powersync/src/devtools/protocol.dart';

import 'databases.dart';

/// A [SqliteConnection] implemented by dispatching queries to a running app
/// over a DevTools RPC protocol.
///
/// Note that most [SqliteConnection] methods are unimplemented, only those
/// needed for the extension are functional.
final class RemoteDatabase extends SqliteConnection {
  final DatabaseReference ref;
  final VmService vmService;

  SyncStatus? currentStatus;

  final StreamController<SyncStatus> _statusController =
      StreamController.broadcast();
  final StreamController<UpdateNotification> _updates =
      StreamController.broadcast();

  Stream<SyncStatus> get syncStatus => _statusController.stream;

  RemoteDatabase(this.ref, this.vmService) {
    _forwardTableUpdates();
    _forwardStatusUpdates();
  }

  void _forwardTableUpdates() {
    int? subscriptionId;
    StreamSubscription<void>? subscription;

    _updates.onListen = () async {
      final response = await request('table-updates-listen');
      subscriptionId = response as int;

      subscription?.cancel();
      subscription = vmService.onExtensionEvent
          .where(
            (e) =>
                e.extensionKind == 'powersync:table-updates' &&
                e.extensionData?.data['subscription'] == subscriptionId,
          )
          .listen((event) {
            final changedTables = event.extensionData!.data['tables'] as List;
            _updates.add(
              UpdateNotification(changedTables.cast<String>().toSet()),
            );
          });
    };
    _updates.onCancel = () {
      subscription?.cancel();
      if (subscriptionId != null) {
        request('unsubscribe', payload: {'id': subscriptionId.toString()});
      }
    };
  }

  void _forwardStatusUpdates() {
    int? subscriptionId;
    StreamSubscription<void>? subscription;

    _statusController.onListen = () async {
      final response = (await request('status-listen')) as Map<String, Object?>;
      subscriptionId = response['id'] as int;

      void addStatus(Map<String, Object?> serialized) {
        _statusController.add(deserializeSyncStatus(serialized));
      }

      addStatus(response['current'] as Map<String, Object?>);

      subscription?.cancel();
      subscription = vmService.onExtensionEvent
          .where(
            (e) =>
                e.extensionKind == 'powersync:status-updates' &&
                e.extensionData?.data['subscription'] == subscriptionId,
          )
          .listen((event) {
            final status =
                event.extensionData!.data['status'] as Map<String, Object?>;
            addStatus(status);
          });
    };
    _statusController.onCancel = () {
      subscription?.cancel();
      if (subscriptionId != null) {
        request('unsubscribe', payload: {'id': subscriptionId.toString()});
      }
    };
  }

  Future<Object?> request(
    String command, {
    Map<String, String> payload = const {},
  }) async {
    final response = await vmService.callServiceExtension(
      'ext.powersync.database',
      isolateId: ref.isolate.id,
      args: {'command': command, 'db': ref.id, ...payload},
    );

    final json = response.json!;
    if (json.containsKey('error')) {
      throw json['error'];
    }

    return json['ok'];
  }

  Future<Map<String, Object?>> serializedSchema() async {
    return (await request('schema')) as Map<String, Object?>;
  }

  @override
  Future<T> abortableReadLock<T>(
    Future<T> Function(SqliteReadContext tx) callback, {
    Future<void>? abortTrigger,
    String? debugContext,
  }) {
    return callback(_WriteContext(this));
  }

  @override
  Future<T> abortableWriteLock<T>(
    Future<T> Function(SqliteWriteContext tx) callback, {
    Future<void>? abortTrigger,
    String? debugContext,
  }) {
    return callback(_WriteContext(this));
  }

  @override
  Future<void> close() async {
    _updates.close();
  }

  @override
  bool get closed => false;

  @override
  Future<bool> getAutoCommit() async {
    return true; // Doesn't matter in devtools extension
  }

  @override
  Future<T> readTransaction<T>(
    Future<T> Function(SqliteReadContext tx) callback, {
    Duration? lockTimeout,
  }) {
    throw UnimplementedError();
  }

  @override
  Stream<UpdateNotification> get updates => _updates.stream;
}

final class _WriteContext implements SqliteWriteContext {
  final RemoteDatabase _database;

  _WriteContext(this._database);

  @override
  bool get closed => false;

  @override
  Future<T> computeWithDatabase<T>(
    Future<T> Function(CommonDatabase db) compute,
  ) {
    throw UnimplementedError();
  }

  @override
  Future<ResultSet> execute(
    String sql, [
    List<Object?> parameters = const [],
  ]) async {
    await _database.request(
      'execute',
      payload: {
        'sql': sql,
        'params': json.encode(parameters.map(encodeSqlValue).toList()),
      },
    );

    return ResultSet([], null, []);
  }

  @override
  Future<void> executeBatch(String sql, List<dynamic> parameterSets) {
    throw UnimplementedError();
  }

  @override
  Future<void> executeMultiple(String sql) async {
    await execute(sql);
  }

  @override
  Future<Row> get(String sql, [List<Object?> parameters = const []]) async {
    return (await getAll(sql, parameters)).first;
  }

  @override
  Future<ResultSet> getAll(
    String sql, [
    List<Object?> parameters = const [],
  ]) async {
    final response =
        (await _database.request(
              'select',
              payload: {
                'sql': sql,
                'params': json.encode(parameters.map(encodeSqlValue).toList()),
              },
            ))!
            as Map<String, Object?>;

    final columnNames = response['columnNames'] as List;

    return ResultSet(columnNames.cast(), null, [
      for (final row in (response['rows'] as List).cast<List>())
        [for (final value in row) decodeSqlValue(value)],
    ]);
  }

  @override
  Future<bool> getAutoCommit() async {
    return false;
  }

  @override
  Future<Row?> getOptional(
    String sql, [
    List<Object?> parameters = const [],
  ]) async {
    return (await getAll(sql, parameters)).firstOrNull;
  }

  @override
  Future<T> writeTransaction<T>(
    Future<T> Function(SqliteWriteContext tx) callback,
  ) {
    throw UnimplementedError();
  }
}
