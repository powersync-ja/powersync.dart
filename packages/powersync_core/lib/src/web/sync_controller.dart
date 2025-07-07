import 'dart:async';
import 'dart:js_interop';

import 'package:powersync_core/powersync_core.dart';
import 'package:powersync_core/src/sync/options.dart';
import 'package:sqlite_async/web.dart';
import 'package:web/web.dart';

import '../database/web/web_powersync_database.dart';
import '../sync/streaming_sync.dart';
import 'sync_worker_protocol.dart';

class SyncWorkerHandle implements StreamingSync {
  final PowerSyncDatabaseImpl database;
  final PowerSyncBackendConnector connector;
  final SyncOptions options;
  late final WorkerCommunicationChannel _channel;

  final StreamController<SyncStatus> _status = StreamController.broadcast();

  SyncWorkerHandle._({
    required this.database,
    required this.connector,
    required this.options,
    required MessagePort sendToWorker,
    required SharedWorker worker,
  }) {
    _channel = WorkerCommunicationChannel(
      port: sendToWorker,
      errors: EventStreamProviders.errorEvent.forTarget(worker),
      logger: database.logger,
      requestHandler: (type, payload) async {
        switch (type) {
          case SyncWorkerMessageType.requestEndpoint:
            final endpoint = await (database.database as WebSqliteConnection)
                .exposeEndpoint();

            return (
              WebEndpoint(
                databaseName: endpoint.connectName,
                databasePort: endpoint.connectPort,
                lockName: endpoint.lockName,
              ),
              [endpoint.connectPort].toJS
            );
          case SyncWorkerMessageType.uploadCrud:
            await connector.uploadData(database);
            return (JSObject(), null);
          case SyncWorkerMessageType.invalidCredentialsCallback:
            final credentials = await connector.prefetchCredentials();
            return (
              credentials != null
                  ? SerializedCredentials.from(credentials)
                  : null,
              null
            );
          case SyncWorkerMessageType.credentialsCallback:
            final credentials = await connector.getCredentialsCached();
            return (
              credentials != null
                  ? SerializedCredentials.from(credentials)
                  : null,
              null
            );
          default:
            throw StateError('Unexpected message type $type');
        }
      },
    );

    _channel.events.listen((data) {
      final (type, payload) = data;
      if (type == SyncWorkerMessageType.notifySyncStatus) {
        _status.add((payload as SerializedSyncStatus).asSyncStatus());
      }
    });
  }

  static Future<SyncWorkerHandle> start({
    required PowerSyncDatabaseImpl database,
    required PowerSyncBackendConnector connector,
    required Uri workerUri,
    required SyncOptions options,
  }) async {
    final worker = SharedWorker(workerUri.toString().toJS);
    final handle = SyncWorkerHandle._(
      options: options,
      database: database,
      connector: connector,
      sendToWorker: worker.port,
      worker: worker,
    );

    // Make sure that the worker is working, or throw immediately.
    await handle._channel.ping();

    return handle;
  }

  Future<void> close() async {
    await abort();
    await _channel.close();
  }

  @override
  Future<void> abort() async {
    await _channel.abortSynchronization();
  }

  @override
  Stream<SyncStatus> get statusStream => _status.stream;

  @override
  Future<void> streamingSync() async {
    await _channel.startSynchronization(
      database.database.openFactory.path,
      ResolvedSyncOptions(options),
      database.schema,
    );
  }
}
