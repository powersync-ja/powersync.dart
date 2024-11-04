/// This file needs to be compiled to JavaScript with the command
/// dart compile js -O4 packages/powersync/lib/src/web/sync_worker.dart -o assets/powersync_sync.worker.js
/// The output should then be included in each project's `web` directory
library;

import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';

import 'package:async/async.dart';
import 'package:fetch_client/fetch_client.dart';
import 'package:powersync/powersync.dart';
import 'package:powersync/sqlite_async.dart';
import 'package:powersync/src/database/powersync_db_mixin.dart';
import 'package:powersync/src/streaming_sync.dart';
import 'package:sqlite_async/web.dart';
import 'package:web/web.dart' hide RequestMode;

import '../bucket_storage.dart';
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
      String databaseIdentifier,
      int crudThrottleTimeMs,
      String? syncParamsEncoded,
      _ConnectedClient client) {
    return _requestedSyncTasks.putIfAbsent(databaseIdentifier, () {
      return _SyncRunner(databaseIdentifier);
    })
      ..registerClient(client, crudThrottleTimeMs, syncParamsEncoded);
  }
}

class _ConnectedClient {
  late WorkerCommunicationChannel channel;
  final _SyncWorker _worker;

  _SyncRunner? _runner;
  StreamSubscription? _logSubscription;

  _ConnectedClient(MessagePort port, this._worker) {
    channel = WorkerCommunicationChannel(
      port: port,
      requestHandler: (type, payload) async {
        switch (type) {
          case SyncWorkerMessageType.startSynchronization:
            final request = payload as StartSynchronization;
            _runner = _worker.referenceSyncTask(request.databaseName,
                request.crudThrottleTimeMs, request.syncParamsEncoded, this);
            return (JSObject(), null);
          case SyncWorkerMessageType.abortSynchronization:
            _runner?.disconnectClient(this);
            _runner = null;
            return (JSObject(), null);
          default:
            throw StateError('Unexpected message type $type');
        }
      },
    );

    _logSubscription = _logger.onRecord.listen((record) {
      final msg = StringBuffer(
          '[${record.loggerName}] ${record.level.name}: ${record.time}: ${record.message}');

      if (record.error != null) {
        msg
          ..writeln()
          ..write(record.error);
      }
      if (record.stackTrace != null) {
        msg
          ..writeln()
          ..write(record.stackTrace);
      }

      channel.notify(SyncWorkerMessageType.logEvent, msg.toString().toJS);
    });
  }

  void markClosed() {
    _logSubscription?.cancel();
    _runner?.unregisterClient(this);
    _runner = null;
  }
}

class _SyncRunner {
  final String identifier;
  int crudThrottleTimeMs = 1;
  String? syncParamsEncoded;

  final StreamGroup<_RunnerEvent> _group = StreamGroup();
  final StreamController<_RunnerEvent> _mainEvents = StreamController();

  StreamingSync? sync;
  _ConnectedClient? databaseHost;
  final connections = <_ConnectedClient>[];

  _SyncRunner(this.identifier) {
    _group.add(_mainEvents.stream);

    Future(() async {
      await for (final event in _group.stream) {
        try {
          switch (event) {
            case _AddConnection(
                :final client,
                :final crudThrottleTimeMs,
                :final syncParamsEncoded
              ):
              connections.add(client);
              var reconnect = false;
              if (this.crudThrottleTimeMs != crudThrottleTimeMs) {
                this.crudThrottleTimeMs = crudThrottleTimeMs;
                reconnect = true;
              }
              if (this.syncParamsEncoded != syncParamsEncoded) {
                this.syncParamsEncoded = syncParamsEncoded;
                reconnect = true;
              }
              if (sync == null) {
                await _requestDatabase(client);
              } else if (reconnect) {
                // Parameters changed - reconnect.
                sync?.abort();
                sync = null;
                await _requestDatabase(client);
              }
            case _RemoveConnection(:final client):
              connections.remove(client);
              if (connections.isEmpty) {
                await sync?.abort();
                sync = null;
              }
            case _DisconnectClient(:final client):
              connections.remove(client);
              await sync?.abort();
              sync = null;
            case _ActiveDatabaseClosed():
              _logger.info('Remote database closed, finding a new client');
              sync?.abort();
              sync = null;

              // The only reliable notification we get for a client closing is
              // when that client is currently hosting the database. Use the
              // opportunity to check whether secondary clients have also closed
              // in the meantime.
              final newHost = await _collectActiveClients();
              if (newHost == null) {
                _logger.info('No client remains');
              } else {
                await _requestDatabase(newHost);
              }
          }
        } catch (e, s) {
          _logger.warning('Error handling $event', e, s);
        }
      }
    });
  }

  /// Pings all current [connections], removing those that don't answer in 5s
  /// (as they are likely closed tabs as well).
  ///
  /// Returns the first client that responds (without waiting for others).
  Future<_ConnectedClient?> _collectActiveClients() async {
    final candidates = connections.toList();
    if (candidates.isEmpty) {
      return null;
    }

    final firstResponder = Completer<_ConnectedClient?>();
    var pendingRequests = candidates.length;

    for (final candidate in candidates) {
      candidate.channel.ping().then((_) {
        pendingRequests--;
        if (!firstResponder.isCompleted) {
          firstResponder.complete(candidate);
        }
      }).timeout(const Duration(seconds: 5), onTimeout: () {
        pendingRequests--;
        candidate.markClosed();
        if (pendingRequests == 0 && !firstResponder.isCompleted) {
          // All requests have timed out, no connection remains
          firstResponder.complete(null);
        }
      });
    }

    return firstResponder.future;
  }

  Future<void> _requestDatabase(_ConnectedClient client) async {
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
    databaseHost = client;

    database.closedFuture.then((_) {
      _logger.fine('Detected closed client');
      client.markClosed();

      if (client == databaseHost) {
        _logger
            .info('Tab providing sync database has gone down, reconnecting...');
        _mainEvents.add(const _ActiveDatabaseClosed());
      }
    });

    final tables = ['ps_crud'];
    final crudThrottleTime = Duration(milliseconds: crudThrottleTimeMs);
    Stream<UpdateNotification> crudStream =
        powerSyncUpdateNotifications(Stream.empty());
    if (database.updates != null) {
      final filteredStream = database.updates!
          .transform(UpdateNotification.filterTablesTransformer(tables));
      crudStream = UpdateNotification.throttleStream(
        filteredStream,
        crudThrottleTime,
        addOne: UpdateNotification.empty(),
      );
    }

    final syncParams = syncParamsEncoded == null
        ? null
        : jsonDecode(syncParamsEncoded!) as Map<String, dynamic>;

    sync = StreamingSyncImplementation(
        adapter: BucketStorage(database),
        credentialsCallback: client.channel.credentialsCallback,
        invalidCredentialsCallback: client.channel.invalidCredentialsCallback,
        uploadCrud: client.channel.uploadCrud,
        crudUpdateTriggerStream: crudStream,
        retryDelay: Duration(seconds: 3),
        client: FetchClient(mode: RequestMode.cors),
        identifier: identifier,
        syncParameters: syncParams);
    sync!.statusStream.listen((event) {
      _logger.fine('Broadcasting sync event: $event');
      for (final client in connections) {
        client.channel.notify(SyncWorkerMessageType.notifySyncStatus,
            SerializedSyncStatus.from(event));
      }
    });
    sync!.streamingSync();
  }

  void registerClient(_ConnectedClient client, int currentCrudThrottleTimeMs,
      String? currentSyncParamsEncoded) {
    _mainEvents.add(_AddConnection(
        client, currentCrudThrottleTimeMs, currentSyncParamsEncoded));
  }

  /// Remove a client, disconnecting if no clients remain..
  void unregisterClient(_ConnectedClient client) {
    _mainEvents.add(_RemoveConnection(client));
  }

  /// Remove a client, and immediately disconnect.
  void disconnectClient(_ConnectedClient client) {
    _mainEvents.add(_DisconnectClient(client));
  }
}

sealed class _RunnerEvent {}

final class _AddConnection implements _RunnerEvent {
  final _ConnectedClient client;
  final int crudThrottleTimeMs;
  final String? syncParamsEncoded;

  _AddConnection(this.client, this.crudThrottleTimeMs, this.syncParamsEncoded);
}

final class _RemoveConnection implements _RunnerEvent {
  final _ConnectedClient client;

  _RemoveConnection(this.client);
}

final class _DisconnectClient implements _RunnerEvent {
  final _ConnectedClient client;

  _DisconnectClient(this.client);
}

final class _ActiveDatabaseClosed implements _RunnerEvent {
  const _ActiveDatabaseClosed();
}
