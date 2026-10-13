/// This file needs to be compiled to JavaScript with the command
/// dart compile js -O4 packages/powersync/lib/src/web/sync_worker.dart -o assets/powersync_sync.worker.js
/// The output should then be included in each project's `web` directory
@internal
library;

import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';

import 'package:async/async.dart';
import 'package:collection/collection.dart';
import 'package:logging/logging.dart';
import 'package:meta/meta.dart';
import 'package:powersync/powersync.dart';
import 'package:sqlite_async/sqlite_async.dart';
import 'package:powersync/src/sync/internal_connector.dart';
import 'package:powersync/src/sync/options.dart';
import 'package:powersync/src/sync/streaming_sync.dart';
import 'package:sqlite_async/web.dart';
import 'package:web/web.dart' hide RequestMode;

import '../database/powersync_database.dart';
import '../platform_specific/web.dart';
import '../sync/bucket_storage.dart';
import 'http/client.dart';
import 'sync_worker_protocol.dart';

final _logger = autoLogger;

class SyncWorker {
  @visibleForTesting
  final Map<String, SyncRunner> requestedSyncTasks = {};

  void trackPort(MessagePort port) {
    ConnectedClient(port, this);
  }

  SyncRunner _referenceSyncTask(
    String databaseIdentifier,
    SyncOptions options,
    String schemaJson,
    List<SubscribedStream> subscriptions,
    ConnectedClient client,
  ) {
    return requestedSyncTasks.putIfAbsent(databaseIdentifier, () {
      return SyncRunner(databaseIdentifier);
    })..registerClient(client, options, schemaJson, subscriptions);
  }
}

@visibleForTesting
class ConnectedClient {
  late WorkerCommunicationChannel channel;
  final SyncWorker _worker;

  SyncRunner? _runner;
  StreamSubscription<LogRecord>? _logSubscription;

  InternalAuthenticator? authenticator;
  InternalMutationUploader? uploader;

  ConnectedClient(MessagePort port, this._worker) {
    channel = WorkerCommunicationChannel(
      port: port,
      requestHandler: (type, payload) async {
        switch (type) {
          case SyncWorkerMessageType.startSynchronization:
            final request = payload as StartSynchronization;
            channel.observeRemoteLockName(request.lockName);

            final recoveredOptions = SyncOptions(
              crudThrottleTime: Duration(
                milliseconds: request.crudThrottleTimeMs,
              ),
              retryDelay: switch (request.retryDelayMs) {
                null => null,
                final retryDelay => Duration(milliseconds: retryDelay),
              },
              params: switch (request.syncParamsEncoded) {
                null => null,
                final encodedParams =>
                  jsonDecode(encodedParams) as Map<String, Object?>,
              },
              syncImplementation: SyncClientImplementation.rust,
              appMetadata: switch (request.appMetadataEncoded) {
                null => null,
                final encodedAppMetadata => Map<String, String>.from(
                  jsonDecode(encodedAppMetadata) as Map<String, dynamic>,
                ),
              },
              httpClient: request.customHttpClient == true
                  ? () => RemoteHttpClient(channel)
                  : null,
              checkpointMode: switch (request.checkpointModeRequestsDelay) {
                null => const CheckpointMode.legacy(),
                final delay => RequestsCheckpointMode.unverifiedDuration(
                  Duration(microseconds: delay),
                ),
              },
              enableDiagnostics: request.diagnostics ?? false,
            );

            final hasAuthenticator = request.hasAuthenticator ?? true;
            final hasUploader = request.hasUploader ?? true;

            authenticator = hasAuthenticator
                ? RemoteAuthenticator(channel)
                : null;
            uploader = hasUploader ? RemoteUploader(channel) : null;

            _runner = _worker._referenceSyncTask(
              request.databaseName,
              recoveredOptions,
              request.schemaJson,
              request.subscriptions?.toDart ?? const [],
              this,
            );
            return (JSObject(), null);
          case SyncWorkerMessageType.abortSynchronization:
            _runner?.disconnectClient(this);
            _runner = null;
            return (JSObject(), null);
          case SyncWorkerMessageType.updateSubscriptions:
            _runner?.updateClientSubscriptions(
              this,
              (payload as UpdateSubscriptions).toDart,
            );
            return (JSObject(), null);
          case SyncWorkerMessageType.requestCheckpoint:
            final sync = _runner!.sync!;
            final checkpoint = await sync.requestCheckpoint();

            // Workers are always compiled to JS, so we can safely assume the
            // value here is a JS bigint.
            return ((checkpoint as JsBigInt64).value, null);
          default:
            throw StateError('Unexpected message type $type');
        }
      },
    );
    channel.closed.whenComplete(markClosed);

    _logSubscription = _logger.onRecord.listen((record) {
      final msg = StringBuffer(
        '[${record.loggerName}] ${record.level.name}: ${record.time}: ${record.message}',
      );

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

  void sendSyncUpdate(SerializedSyncStatusUpdate status) {
    channel.notify(SyncWorkerMessageType.notifySyncStatus, status);
  }

  void sendDiagnosticsEvent(String serializedEvent) {
    channel.notify(
      SyncWorkerMessageType.handleDiagnostics,
      serializedEvent.toJS,
    );
  }
}

@visibleForTesting
class SyncRunner {
  final String identifier;
  ResolvedSyncOptions options = ResolvedSyncOptions(SyncOptions());
  String schemaJson = '{}';

  final StreamGroup<_RunnerEvent> _group = StreamGroup();
  final StreamController<_RunnerEvent> _mainEvents = StreamController();

  StreamingSyncImplementation? sync;
  final SerializedSyncStatusUpdate _collectedStatusUpdates =
      SerializedSyncStatusUpdate();
  ConnectedClient? databaseHost;
  final connections = <ConnectedClient, List<SubscribedStream>>{};
  List<SubscribedStream> currentStreams = [];

  SyncRunner(this.identifier) {
    _group.add(_mainEvents.stream);

    Future(() async {
      await for (final event in _group.stream) {
        try {
          switch (event) {
            case _AddConnection(
              :final client,
              :final options,
              :final schemaJson,
              :final subscriptions,
            ):
              connections[client] = subscriptions;
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
              } else {
                reindexSubscriptions();
              }

              // Inform the client about the current sync status.
              client.sendSyncUpdate(_collectedStatusUpdates);
            case _RemoveConnection(:final client):
              connections.remove(client);
              if (connections.isEmpty) {
                await sync?.abort();
                sync = null;
              } else if (client == databaseHost) {
                await _activeClientHasClosed();
              }
            case _DisconnectClient(:final client):
              connections.remove(client);
              await sync?.abort();
              sync = null;
            case _ClientSubscriptionsChanged(
              :final client,
              :final subscriptions,
            ):
              connections[client] = subscriptions;
              reindexSubscriptions();
          }
        } catch (e, s) {
          _logger.warning('Error handling $event', e, s);
        }
      }
    });
  }

  Future<void> _activeClientHasClosed() async {
    _logger.info('Remote database closed, finding a new client');
    await sync?.abort();
    sync = null;

    final newHost = await _collectActiveClients();
    if (newHost == null) {
      _logger.info('No client remains');
    } else {
      await _requestDatabase(newHost);
    }
  }

  /// Updates [currentStreams] to the union of values in [connections].
  void reindexSubscriptions() {
    final before = currentStreams.toSet();
    final after = connections.values.flattenedToSet;
    if (!const SetEquality<SubscribedStream>().equals(before, after)) {
      _logger.info(
        'Subscriptions across tabs have changed, checking whether a reconnect is necessary',
      );
      currentStreams = after.toList();
      sync?.updateSubscriptions(currentStreams);
    }
  }

  /// Pings all current [connections], removing those that don't answer in 5s
  /// (as they are likely closed tabs as well).
  ///
  /// Returns the first client that responds (without waiting for others).
  Future<ConnectedClient?> _collectActiveClients() async {
    final candidates = connections.keys.toList();
    if (candidates.isEmpty) {
      return null;
    }

    final firstResponder = Completer<ConnectedClient?>();
    var pendingRequests = candidates.length;

    for (final candidate in candidates) {
      candidate.channel
          .ping()
          .then((_) {
            pendingRequests--;
            if (!firstResponder.isCompleted) {
              firstResponder.complete(candidate);
            }
          })
          .timeout(
            const Duration(seconds: 5),
            onTimeout: () {
              pendingRequests--;
              candidate.markClosed();
              if (pendingRequests == 0 && !firstResponder.isCompleted) {
                // All requests have timed out, no connection remains
                firstResponder.complete(null);
              }
            },
          );
    }

    return firstResponder.future;
  }

  Future<void> _requestDatabase(ConnectedClient client) async {
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
    });

    final tables = ['ps_crud'];
    Stream<UpdateNotification> crudStream = powerSyncUpdateNotifications(
      Stream.empty(),
    );
    final filteredStream = database.updates.transform(
      UpdateNotification.filterTablesTransformer(tables),
    );
    crudStream = UpdateNotification.throttleStream(
      filteredStream,
      options.crudThrottleTime,
      addOne: UpdateNotification.empty(),
    );

    currentStreams = connections.values.flattenedToSet.toList();
    final createdSync = sync = StreamingSyncImplementation(
      adapter: BucketStorage(database),
      schemaJson: schemaJson,
      connector: InternalConnector(client.authenticator, client.uploader),
      crudUpdateTriggerStream: crudStream,
      options: options,
      identifier: identifier,
      activeSubscriptions: currentStreams,
      logger: _logger,
    );
    createdSync.statusUpdates.listen((event) {
      _logger.fine('Broadcasting status update: $event');
      final serialized = SerializedSyncStatusUpdate();

      if (event.core case final core?) {
        serialized.core = _collectedStatusUpdates.core = json
            .encode(core.originalJson)
            .toJS;
      }
      if (event.uploading case final uploading?) {
        serialized.uploading = _collectedStatusUpdates.uploading =
            uploading.toJS;
      }
      if (event.downloadError != null) {
        serialized.downloadError = _collectedStatusUpdates.downloadError =
            SerializedSyncStatusUpdate.serializeError(event.downloadError);
      }
      if (event.uploadError != null) {
        serialized.uploadError = _collectedStatusUpdates.uploadError =
            SerializedSyncStatusUpdate.serializeError(event.uploadError);
      }

      for (final client in connections.keys) {
        client.sendSyncUpdate(serialized);
      }
    });
    createdSync.diagnostics.listen((event) {
      _logger.fine('Broadcasting diagnostic event: $event');
      for (final client in connections.keys) {
        client.sendDiagnosticsEvent(event);
      }
    });
    createdSync.streamingSync();
  }

  void registerClient(
    ConnectedClient client,
    SyncOptions options,
    String schemaJson,
    List<SubscribedStream> subscriptions,
  ) {
    // All connections in a sync runner must all use the same sync mode
    // (download only / upload only / both).
    if (connections.keys.firstOrNull case final existingClient?) {
      final hasAuthenticator = client.authenticator != null;
      final hasUploader = client.uploader != null;

      final shouldHaveAuthenticator = existingClient.authenticator != null;
      final shouldHaveUploader = existingClient.uploader != null;

      if ((hasAuthenticator != shouldHaveAuthenticator) ||
          (hasUploader != shouldHaveUploader)) {
        throw StateError(
          'Different tabs connecting in different modes (download-only / '
          'upload-only / full) is not supported',
        );
      }
    }

    _mainEvents.add(_AddConnection(client, options, schemaJson, subscriptions));
  }

  /// Remove a client, disconnecting if no clients remain..
  void unregisterClient(ConnectedClient client) {
    _mainEvents.add(_RemoveConnection(client));
  }

  /// Remove a client, and immediately disconnect.
  void disconnectClient(ConnectedClient client) {
    _mainEvents.add(_DisconnectClient(client));
  }

  void updateClientSubscriptions(
    ConnectedClient client,
    List<SubscribedStream> subscriptions,
  ) {
    _mainEvents.add(_ClientSubscriptionsChanged(client, subscriptions));
  }
}

sealed class _RunnerEvent {}

final class _AddConnection implements _RunnerEvent {
  final ConnectedClient client;
  final SyncOptions options;
  final String schemaJson;
  final List<SubscribedStream> subscriptions;

  _AddConnection(
    this.client,
    this.options,
    this.schemaJson,
    this.subscriptions,
  );
}

final class _RemoveConnection implements _RunnerEvent {
  final ConnectedClient client;

  _RemoveConnection(this.client);
}

final class _DisconnectClient implements _RunnerEvent {
  final ConnectedClient client;

  _DisconnectClient(this.client);
}

final class _ClientSubscriptionsChanged implements _RunnerEvent {
  final ConnectedClient client;
  final List<SubscribedStream> subscriptions;

  _ClientSubscriptionsChanged(this.client, this.subscriptions);
}
