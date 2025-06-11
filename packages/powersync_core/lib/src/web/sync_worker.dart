/// This file needs to be compiled to JavaScript with the command
/// dart compile js -O4 packages/powersync/lib/src/web/sync_worker.dart -o assets/powersync_sync.worker.js
/// The output should then be included in each project's `web` directory
library;

import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';

import 'package:async/async.dart';
import 'package:http/browser_client.dart';
import 'package:logging/logging.dart';
import 'package:powersync_core/powersync_core.dart';
import 'package:powersync_core/sqlite_async.dart';
import 'package:powersync_core/src/database/powersync_db_mixin.dart';
import 'package:powersync_core/src/sync/internal_connector.dart';
import 'package:powersync_core/src/sync/options.dart';
import 'package:powersync_core/src/sync/streaming_sync.dart';
import 'package:sqlite_async/web.dart';
import 'package:web/web.dart' hide RequestMode;

import 'sync_worker_protocol.dart';
import 'web_bucket_storage.dart';

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

  _SyncRunner referenceSyncTask(String databaseIdentifier, SyncOptions options,
      String schemaJson, _ConnectedClient client) {
    return _requestedSyncTasks.putIfAbsent(databaseIdentifier, () {
      return _SyncRunner(databaseIdentifier);
    })
      ..registerClient(
        client,
        options,
        schemaJson,
      );
  }
}

class _ConnectedClient {
  late WorkerCommunicationChannel channel;
  final _SyncWorker _worker;

  _SyncRunner? _runner;
  StreamSubscription<LogRecord>? _logSubscription;

  _ConnectedClient(MessagePort port, this._worker) {
    channel = WorkerCommunicationChannel(
      port: port,
      requestHandler: (type, payload) async {
        switch (type) {
          case SyncWorkerMessageType.startSynchronization:
            final request = payload as StartSynchronization;
            final recoveredOptions = SyncOptions(
              crudThrottleTime:
                  Duration(milliseconds: request.crudThrottleTimeMs),
              retryDelay: switch (request.retryDelayMs) {
                null => null,
                final retryDelay => Duration(milliseconds: retryDelay),
              },
              params: switch (request.syncParamsEncoded) {
                null => null,
                final encodedParams =>
                  jsonDecode(encodedParams) as Map<String, Object?>,
              },
              syncImplementation: switch (request.implementationName) {
                null => SyncClientImplementation.defaultClient,
                final name => SyncClientImplementation.values.byName(name),
              },
            );

            _runner = _worker.referenceSyncTask(request.databaseName,
                recoveredOptions, request.schemaJson, this);
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
  ResolvedSyncOptions options = ResolvedSyncOptions(SyncOptions());
  String schemaJson = '{}';

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
                :final options,
                :final schemaJson,
              ):
              connections.add(client);
              final (newOptions, reconnect) = this.options.applyFrom(options);
              this.options = newOptions;
              this.schemaJson = schemaJson;

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
    Stream<UpdateNotification> crudStream =
        powerSyncUpdateNotifications(Stream.empty());
    if (database.updates != null) {
      final filteredStream = database.updates!
          .transform(UpdateNotification.filterTablesTransformer(tables));
      crudStream = UpdateNotification.throttleStream(
        filteredStream,
        options.crudThrottleTime,
        addOne: UpdateNotification.empty(),
      );
    }

    sync = StreamingSyncImplementation(
      adapter: WebBucketStorage(database),
      schemaJson: client._runner!.schemaJson,
      connector: InternalConnector(
        getCredentialsCached: client.channel.credentialsCallback,
        prefetchCredentials: ({required bool invalidate}) async {
          return await client.channel.invalidCredentialsCallback();
        },
        uploadCrud: client.channel.uploadCrud,
      ),
      crudUpdateTriggerStream: crudStream,
      options: options,
      client: BrowserClient(),
      identifier: identifier,
    );
    sync!.statusStream.listen((event) {
      _logger.fine('Broadcasting sync event: $event');
      for (final client in connections) {
        client.channel.notify(SyncWorkerMessageType.notifySyncStatus,
            SerializedSyncStatus.from(event));
      }
    });
    sync!.streamingSync();
  }

  void registerClient(
      _ConnectedClient client, SyncOptions options, String schemaJson) {
    _mainEvents.add(_AddConnection(client, options, schemaJson));
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
  final SyncOptions options;
  final String schemaJson;

  _AddConnection(this.client, this.options, this.schemaJson);
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
