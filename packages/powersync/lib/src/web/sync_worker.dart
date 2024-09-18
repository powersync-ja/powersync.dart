/// This file needs to be compiled to JavaScript with the command
/// dart compile js -O4 packages/powersync/lib/src/web/sync_worker.worker.dart -o assets/db_worker.js
/// The output should then be included in each project's `web` directory
library;

import 'dart:async';
import 'dart:js_interop';

import 'package:async/async.dart';
import 'package:fetch_client/fetch_client.dart';
import 'package:powersync/powersync.dart';
import 'package:powersync/src/streaming_sync.dart';
import 'package:sqlite_async/web.dart';
import 'package:web/web.dart' hide RequestMode;

import '../bucket_storage.dart';
import '../database/powersync_db_mixin.dart';
import 'sync_worker_protocol.dart';

final _logger = autoLogger;

void main() {
  _SyncWorker().start();
}

class _SyncWorker {
  final SharedWorkerGlobalScope _self;
  final Map<String, _SyncRunner> _requestedSyncTasks = {};

  _SyncWorker() : _self = globalContext as SharedWorkerGlobalScope;

  void start() async {
    // Start listening for connect events, each signifies a client connecting
    // to this worker.
    EventStreamProviders.connectEvent.forTarget(_self).listen((e) {
      final ports = (e as MessageEvent).ports.toDart;
      for (final port in ports) {
        _ConnectedClient(port, this);
      }
    });
  }

  _SyncRunner referenceSyncTask(
      String databaseIdentifier, _ConnectedClient client) {
    return _requestedSyncTasks.putIfAbsent(databaseIdentifier, () {
      return _SyncRunner(databaseIdentifier);
    })
      ..registerClient(client);
  }
}

class _ConnectedClient {
  late WorkerCommunicationChannel channel;
  final _SyncWorker _worker;

  _SyncRunner? _runner;

  _ConnectedClient(MessagePort port, this._worker) {
    channel = WorkerCommunicationChannel(
      port: port,
      requestHandler: (type, payload) async {
        switch (type) {
          case SyncWorkerMessageType.startSynchronization:
            final request = payload as StartSynchronization;
            _runner = _worker.referenceSyncTask(request.databaseName, this);
            return (JSObject(), null);
          case SyncWorkerMessageType.abortSynchronization:
            _runner?.unregisterClient(this);
            _runner = null;
            return (JSObject(), null);
          default:
            throw StateError('Unexpected message type $type');
        }
      },
    );
  }
}

class _SyncRunner {
  final String identifier;

  final StreamGroup<_RunnerEvent> _group = StreamGroup();
  final StreamController<_RunnerEvent> _mainEvents = StreamController();

  _SyncRunner(this.identifier) {
    _group.add(_mainEvents.stream);

    Future(() async {
      final connections = <_ConnectedClient>[];
      StreamingSync? sync;

      await for (final event in _group.stream) {
        try {
          switch (event) {
            case _AddConnection(:final client):
              connections.add(client);
              if (sync == null) {
                _logger.info('Sync setup: Requesting database');

                // This is the first client, ask for a database connection
                final connection = await client.channel.requestDatabase();
                _logger.info('Sync setup: Connecting to endpoint');
                final database = await WebSqliteConnection.connectToEndpoint((
                  connectPort: connection.databasePort,
                  connectName: connection.databaseName,
                  lockName: connection.lockName,
                ));
                _logger.info('Sync setup: Has database, starting sync!');

                // todo: Detect client going down (sqlite_web exposes this), fall
                // back to other connection in that case.

                sync = StreamingSyncImplementation(
                  adapter: BucketStorage(database),
                  credentialsCallback: client.channel.credentialsCallback,
                  invalidCredentialsCallback:
                      client.channel.invalidCredentialsCallback,
                  uploadCrud: client.channel.uploadCrud,
                  updateStream: powerSyncUpdateNotifications(
                      database.updates ?? const Stream.empty()),
                  retryDelay: Duration(seconds: 3),
                  client: FetchClient(mode: RequestMode.cors),
                  identifier: identifier,
                );
                sync.statusStream.listen((event) {
                  _logger.fine('Broadcasting sync event: $event');
                  for (final client in connections) {
                    client.channel.notify(
                        SyncWorkerMessageType.notifySyncStatus,
                        SerializedSyncStatus.from(event));
                  }
                });
                sync.streamingSync();
              }
            case _RemoveConnection(:final client):
              connections.remove(client);
              if (connections.isEmpty) {
                await sync?.abort();
                sync = null;
              }
          }
        } catch (e, s) {
          _logger.warning('Error handling $event', e, s);
        }
      }
    });
  }

  void registerClient(_ConnectedClient client) {
    _mainEvents.add(_AddConnection(client));
  }

  void unregisterClient(_ConnectedClient client) {
    _mainEvents.add(_RemoveConnection(client));
  }
}

sealed class _RunnerEvent {}

final class _AddConnection implements _RunnerEvent {
  final _ConnectedClient client;

  _AddConnection(this.client);
}

final class _RemoveConnection implements _RunnerEvent {
  final _ConnectedClient client;

  _RemoveConnection(this.client);
}
