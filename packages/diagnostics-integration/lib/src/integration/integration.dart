import 'dart:async';
import 'dart:js_interop';

import 'package:collection/collection.dart';
import 'package:powersync/powersync.dart';
import 'package:riverpod/riverpod.dart';

import '../state/databases.dart';
import '../state/remote_database.dart';
import '../state/service.dart';
import '../state/sync_status.dart';
import 'types.dart';

@JS('JSON.stringify')
external JSString _jsonEncode(JSAny a);

final class DartSdkIntegration(final Ref _ref) {
  RemoteDatabase _requireDatabase() {
    final db = _ref.read(selectedDatabase);
    if (db == null) {
      throw StateError('No database selected');
    }

    return db;
  }

  Future<QueryResult> _runQuery(QueryParams params) async {
    final database = _requireDatabase();

    final rs = await database.getAll(
      params.sql.toDart,
      params.params?.toDart.map((e) => e.dartify()).toList() ?? const [],
    );

    return QueryResult(
      columns: rs.columnNames.map((e) => e.toJS).toList().toJS,
      rows: [for (final row in rs) row.jsify() as JSObject].toJS,
      rowCount: rs.length,
    );
  }

  Future<JSAny?> _getSchema() async {
    final schema = await _requireDatabase().serializedSchema();

    return schema.jsify();
  }

  Future<ProtocolInfo> _getInfo() async {
    final db = _requireDatabase();
    final coreVersion = await db.get('SELECT powersync_rs_version()');
    final clientId = await db.get('SELECT powersync_client_id()');
    final credentials = _ref.read(lastCredentials);
    final status = _ref.read(syncStatus);

    return ProtocolInfo(
      endpoint: credentials?.original.endpoint,
      userId: credentials?.userId,
      clientId: clientId.columnAt(0) as String,
      connectionMethod: 'http',
      params: null, // TODO: Expose these
      connected: status != null && (status.connected || status.connecting),
      sqliteCoreVersion: coreVersion.columnAt(0) as String,
      sdk: 'Dart',
    );
  }

  Future<SyncState> _currentSyncStatus() async {
    final completer = Completer<SyncStatus>();
    ProviderSubscription<SyncStatus?>? subscription;
    subscription = _ref.listen(syncStatus, (_, status) {
      if (status != null) {
        completer.complete(status);
        subscription?.close();
      }
    }, fireImmediately: true);

    return (await completer.future).toDiagnosticsSyncState();
  }

  Future<UploadQueueState> _uploadQueueStats() async {
    final pending = await _ref.read(pendingCrudItems.future);
    return UploadQueueState(count: pending, size: null);
  }

  Future<void> _action(ActionRequest request) async {
    final db = _requireDatabase();

    switch (ActionName.values.byName(request.action)) {
      case ActionName.reconnect:
        throw UnimplementedError();
      case ActionName.disconnect:
        await db.request('disconnect');
      case ActionName.clearData:
        await db.request('clear-data');
      case ActionName.requestCheckpoint:
        await db.request('request-checkpoint');
      case ActionName.subscribeStream:
        final args = request.args!;
        await db.request(
          'sync-subscribe',
          payload: {
            'name': args.name,
            if (args.params case final params?)
              'params': _jsonEncode(params).toDart
            else
              'params': '{}',
            if (args.ttl case final ttl?) 'ttl': ttl.toString(),
            if (args.priority case final priority?)
              'priority': priority.toString(),
          },
        );
      case ActionName.unsubscribeStream:
        final args = request.args!;
        await db.request(
          'sync-unsubscribe',
          payload: {
            'name': args.name,
            if (args.params case final params?)
              'params': _jsonEncode(params).toDart
            else
              'params': '{}',
          },
        );
    }
  }

  Future<void> _selectSource(String? sourceId) async {
    DatabaseReference? db;

    if (sourceId != null) {
      final id = int.parse(sourceId);
      final databases = _ref.read(databaseList).value;
      db = databases?.firstWhereOrNull((db) => db.id == id);
    }

    _ref.read(selectedDatabase.notifier).state = db == null
        ? null
        : RemoteDatabase(db, _ref.read(serviceProvider).requireValue);
  }

  Future<void> _close() async {}

  @JSExport()
  JSPromise<QueryResult> runQuery(QueryParams params) => _runQuery(params).toJS;

  @JSExport()
  JSPromise<JSAny?> getSchema() => _getSchema().toJS;

  @JSExport()
  JSPromise<ProtocolInfo> getInfo() => _getInfo().toJS;

  @JSExport()
  JSPromise<SyncState> currentSyncStatus() => _currentSyncStatus().toJS;

  @JSExport()
  JSPromise<UploadQueueState> getUploadQueueStats() => _uploadQueueStats().toJS;

  @JSExport()
  JSPromise<Unsubscribe> observeEvents(
    JSFunction<void Function(JSObject)> handler,
  ) {
    // This observes status, streams, buckets, uploadQueue, logs and core
    // diagnostic events.
    final status = _ref.listen(syncStatus, (_, state) {
      if (state != null) {
        handler.callAsFunction(
          null,
          DiagnosticsEvent.status(state.toDiagnosticsSyncState()),
        );

        if (state.syncStreams case final streams?) {
          handler.callAsFunction(
            null,
            DiagnosticsEvent.streams(
              [for (final stream in streams) stream.toStreamState()].toJS,
            ),
          );
        }
      }
    }, fireImmediately: true);
    final uploadQueue = _ref.listen(pendingCrudItems, (old, state) {
      if (state is AsyncData && old?.value != state.value) {
        handler.callAsFunction(
          null,
          DiagnosticsEvent.uploadQueue(
            UploadQueueState(count: state.value!, size: null),
          ),
        );
      }
    }, fireImmediately: true);
    final buckets = _ref.listen(bucketState, (_, state) {
      if (state.value case final buckets?) {
        handler.callAsFunction(null, DiagnosticsEvent.buckets(buckets.toJS));
      }
    }, fireImmediately: true);

    void unsubscribe() {
      uploadQueue.close();
      status.close();
      buckets.close();
    }

    return Future.syncValue(unsubscribe.toJS).toJS;
  }

  @JSExport()
  JSPromise action(ActionRequest request) => _action(request).toJS;

  @JSExport()
  JSPromise<Unsubscribe> observeSources(
    JSFunction<void Function(JSArray<DiagnosticsSource>)> handler,
  ) {
    final subscription = _ref.listen(databaseList, (_, state) {
      if (state.value case final databases?) {
        final sources = <DiagnosticsSource>[
          for (final db in databases)
            DiagnosticsSource(
              id: db.id.toString(),
              sdk: '${db.name} at ${db.path}',
            ),
        ];

        handler.callAsFunction(null, sources.toJS);
      }
    });

    void unsubscribe() => subscription.close();
    return Future.syncValue(unsubscribe.toJS).toJS;
  }

  @JSExport()
  JSPromise selectSource(JSString? sourceId) =>
      _selectSource(sourceId?.toDart).toJS;

  @JSExport()
  JSPromise close() => _close().toJS;
}
