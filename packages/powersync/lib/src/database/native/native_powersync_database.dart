import 'dart:async';
import 'dart:convert';
import 'dart:isolate';
import 'package:meta/meta.dart';

import 'package:logging/logging.dart';
import 'package:powersync/src/abort_controller.dart';
import 'package:powersync/src/platform_specific/int64.dart';
import 'package:powersync/src/sync/bucket_storage.dart';
import 'package:powersync/src/connector.dart';
import 'package:powersync/src/database/powersync_database.dart';
import 'package:powersync/src/isolate_completer.dart';
import 'package:powersync/src/log_internal.dart';
import 'package:powersync/src/sync/internal_connector.dart';
import 'package:powersync/src/sync/options.dart';
import 'package:powersync/src/sync/streaming_sync.dart';
import 'package:sqlite_async/sqlite_async.dart';

import '../../sync/checkpoint_request.dart';
import '../../sync/status_update.dart';
import 'sync_isolate_protocol.dart';

/// A PowerSync managed database.
///
///Native implementation for [PowerSyncDatabase]
///
/// Use one instance per database file.
///
/// Use [PowerSyncDatabase.connect] to connect to the PowerSync service,
/// to keep the local database in sync with the remote database.
///
/// All changes to local tables are automatically recorded, whether connected
/// or not. Once connected, the changes are uploaded.
final class NativePowerSyncDatabase extends BasePowerSyncDatabase {
  NativePowerSyncDatabase({
    required super.schema,
    required super.database,
    required super.logger,
    required super.platform,
  });

  @override
  @internal
  Future<RemoteStreamingSyncHandle> connectInternal({
    required InternalConnector connector,
    required ResolvedSyncOptions options,
    required List<SubscribedStream> initiallyActiveStreams,
    required Stream<List<SubscribedStream>> activeStreams,
    required AbortController abort,
    required Zone asyncWorkZone,
  }) async {
    bool triedSpawningIsolate = false;
    StreamSubscription<void>? activeStreamsSubscription;
    final receiveMessages = ReceivePort();
    final receiveUnhandledErrors = ReceivePort();
    final results = IsolateResultCollection();
    final receiveExit = ReceivePort();
    final mutexServer = MutexServer({
      'sync': group.syncMutex,
      'crud': group.crudMutex,
    });
    final diagnostics = StreamController<String>();
    // Connector calls currently being handled for the sync isolate, keyed by
    // their abort token.
    final pendingConnectorCalls = <int, Completer<void>>{};

    SyncIsolatePort? initPort;
    final hasInitPort = Completer<void>();
    final receivedIsolateExit = Completer<void>();

    Future<void> waitForShutdown() async {
      // Only complete the abortion signal after the isolate shuts down. This
      // ensures absolutely no trace of this sync iteration remains.
      if (triedSpawningIsolate) {
        await receivedIsolateExit.future;
      }

      // Cleanup
      results.close();
      activeStreamsSubscription?.cancel();
      receiveMessages.close();
      receiveUnhandledErrors.close();
      receiveExit.close();
      diagnostics.close();
      mutexServer.handleChildIsolateExit();
      for (final pending in pendingConnectorCalls.values) {
        pending.complete();
      }
      pendingConnectorCalls.clear();

      abort.completeAbort();
    }

    Future<void> close() async {
      initPort?.sendClose();
      await waitForShutdown();
    }

    Future<void> handleConnectorCall<T>(
      PortCompleter<T> completer,
      int abortToken,
      Future<T> Function(Future<void> abortSignal) body,
    ) {
      final abortSignal = pendingConnectorCalls[abortToken] = Completer();
      return completer.handle(() => body(abortSignal.future)).whenComplete(() {
        if (pendingConnectorCalls.remove(abortToken) case final signal?) {
          signal.complete();
        }
      });
    }

    Future<void> handleMessage(Object? data) async {
      final (type, payload) = data as SyncIsolateToClientMessage;
      switch (type) {
        case SyncIsolateToClientMessageType.getCredentialsCached:
          final (completer, abortToken) =
              payload as (PortCompleter<PowerSyncCredentials?>, int);
          await handleConnectorCall(completer, abortToken, (abortSignal) async {
            final token = await connector.authenticator!.getCredentialsCached(
              abortSignal,
            );
            logger.fine('Credentials: $token');
            return token;
          });
        case SyncIsolateToClientMessageType.prefetchCredentials:
          logger.fine('Refreshing credentials');
          final (completer, abortToken, invalidate) =
              payload as (PortCompleter<PowerSyncCredentials?>, int, bool);

          await handleConnectorCall(completer, abortToken, (abortSignal) {
            return connector.authenticator!.prefetchCredentials(
              invalidate: invalidate,
              abortSignal: abortSignal,
            );
          });
        case SyncIsolateToClientMessageType.init:
          final port = initPort = SyncIsolatePort(payload as SendPort);
          hasInitPort.complete();

          activeStreamsSubscription = activeStreams.listen((streams) {
            port.sendChangedSubscriptions(streams);
          });
        case SyncIsolateToClientMessageType.uploadCrud:
          final (completer, abortToken) = payload as (PortCompleter<void>, int);
          await handleConnectorCall(completer, abortToken, (abortSignal) {
            return connector.uploader!.upload(abortSignal);
          });
        case SyncIsolateToClientMessageType.customCheckpointRequest:
          final (completer, abortToken, clientId, requestId) =
              payload as (PortCompleter<String?>, int, String, String);
          await handleConnectorCall(completer, abortToken, (abortSignal) async {
            return await connector.authenticator!.postCheckpointRequest(
              clientId,
              requestId,
              abortSignal,
            );
          });
        case SyncIsolateToClientMessageType.abortConnectorCall:
          pendingConnectorCalls.remove(payload as int)?.complete();
        case SyncIsolateToClientMessageType.statusUpdate:
          final update = payload as SyncStatusUpdate;
          if (update.downloadError case final SerializedError e) {
            update.downloadError = e.recoverError();
          }
          if (update.uploadError case final SerializedError e) {
            update.uploadError = e.recoverError();
          }

          setStatus(update.applyTo(currentStatus));
        case SyncIsolateToClientMessageType.diagnostics:
          diagnostics.add(payload as String);
        case SyncIsolateToClientMessageType.log:
          LogRecord record = payload as LogRecord;
          logger.log(
            record.level,
            record.message,
            record.error,
            record.stackTrace,
          );
        case SyncIsolateToClientMessageType.mutexAcquire:
          final (name, id) = payload as (String, int);
          mutexServer.acquireRequest(initPort!, name, id);
        case SyncIsolateToClientMessageType.mutexRelease:
          mutexServer.releaseRequest(payload as int);
      }
    }

    // This function is called in a Zone marking the connection lock as locked.
    // This is used to prevent reentrant calls to the lock (which would be a
    // deadlock). However, the lock is returned as soon as this function
    // returns - and handleMessage may run later. So, make sure we run those
    // callbacks in the parent zone.
    receiveMessages.listen(asyncWorkZone.bindUnaryCallback(handleMessage));

    receiveUnhandledErrors.listen((message) async {
      // Sample error:
      // flutter: [PowerSync] WARNING: 2023-06-28 16:34:11.566122: Sync Isolate error
      // flutter: [Connection closed while receiving data, #0      IOClient.send.<anonymous closure> (package:http/src/io_client.dart:76:13)
      // #1      Stream.handleError.<anonymous closure> (dart:async/stream.dart:929:16)
      // #2      _HandleErrorStream._handleError (dart:async/stream_pipe.dart:269:17)
      // #3      _ForwardingStreamSubscription._handleError (dart:async/stream_pipe.dart:157:13)
      // #4      _HttpClientResponse.listen.<anonymous closure> (dart:_http/http_impl.dart:707:16)
      // ...
      logger.severe('Sync Isolate error', message);

      // Fatal errors are enabled, so the isolate will exit soon, causing us to
      // complete the abort controller which will make the db mixin reconnect if
      // necessary. There's no need to reconnect manually.
    });

    // Don't spawn isolate if this operation was cancelled already.
    if (abort.aborted) {
      await waitForShutdown();
      throw AbortException('connectInternal');
    }

    receiveExit.listen((message) {
      logger.fine('Sync Isolate exit');
      receivedIsolateExit.complete();
    });

    // Spawning the isolate can't be interrupted
    triedSpawningIsolate = true;
    await Isolate.spawn(
      _syncIsolate,
      _PowerSyncDatabaseIsolateArgs(
        SyncClientPort(receiveMessages.sendPort),
        database.openFactory.path,
        options,
        jsonEncode(schema),
        connector.authenticator != null,
        connector.uploader != null,
      ),
      debugName: 'Sync ${database.openFactory.path}',
      onError: receiveUnhandledErrors.sendPort,
      errorsAreFatal: true,
      onExit: receiveExit.sendPort,
    );
    await hasInitPort.future;

    // Automatically complete the abort controller once the isolate exits.
    unawaited(
      Future.any([
        abort.onAbort,
        receivedIsolateExit.future,
      ]).whenComplete(close),
    );

    return _IsolateSyncHandle(initPort!, results, diagnostics.stream);
  }
}

class _PowerSyncDatabaseIsolateArgs {
  final SyncClientPort sPort;
  final String databaseName;
  final ResolvedSyncOptions options;
  final String schemaJson;
  final bool hasAuthenticator;
  final bool hasUploader;

  _PowerSyncDatabaseIsolateArgs(
    this.sPort,
    this.databaseName,
    this.options,
    this.schemaJson,
    this.hasAuthenticator,
    this.hasUploader,
  );
}

Future<void> _syncIsolate(_PowerSyncDatabaseIsolateArgs args) async {
  final sPort = args.sPort;
  final rPort = ReceivePort();
  final results = IsolateResultCollection();

  // Because the original database is still active at the time this is called,
  // creating another database at the same path will use the same underlying
  // connection pool.
  final database = SqliteDatabase(path: args.databaseName);
  final mutexes = RemoteMutexes(sPort);

  StreamingSyncImplementation? openedStreamingSync;

  Completer<void> shutdownCompleter = Completer();

  Future<void> shutdown() {
    if (!shutdownCompleter.isCompleted) {
      shutdownCompleter.complete(
        Future(() async {
          await openedStreamingSync?.abort();
          await database.close();

          rPort.close();
          results.close();
        }),
      );
    }

    return shutdownCompleter.future;
  }

  rPort.listen((message) async {
    final (type, payload) = message as ClientToSyncIsolateMessage;
    switch (type) {
      case ClientToSyncIsolateMessageType.close:
        shutdown();
      case ClientToSyncIsolateMessageType.changedSubscriptions:
        openedStreamingSync?.updateSubscriptions(
          payload as List<SubscribedStream>,
        );
      case ClientToSyncIsolateMessageType.mutexGranted:
        mutexes.markGranted(payload as int);
      case ClientToSyncIsolateMessageType.requestCheckpoint:
        (payload as PortCompleter<Int64>).handle(() async {
          final sync = openedStreamingSync;
          if (sync == null) throw disconnected;

          return await sync.requestCheckpoint();
        });
    }
  });
  sPort.sendInit(rPort.sendPort);

  // Is there a way to avoid the overhead if logging is not enabled?
  // This only takes effect in this isolate.
  isolateLogger.level = Level.ALL;
  isolateLogger.onRecord.listen((record) {
    var copy = LogRecord(
      record.level,
      record.message,
      record.loggerName,
      record.error,
      record.stackTrace,
    );
    sPort.sendLog(copy);
  });

  runZonedGuarded(
    () async {
      final storage = BucketStorage(database);
      final connectorCalls = _ConnectorCalls(results, sPort);
      final sync = openedStreamingSync = StreamingSyncImplementation(
        adapter: storage,
        schemaJson: args.schemaJson,
        connector: InternalConnector(
          args.hasAuthenticator
              ? _ClientPortAuthenticator(connectorCalls)
              : null,
          args.hasUploader ? _ClientPortUploader(connectorCalls) : null,
        ),
        crudUpdateTriggerStream: database.onChange([
          'ps_crud',
        ], throttle: args.options.crudThrottleTime),
        options: args.options,
        syncMutex: mutexes.mutex('sync'),
        crudMutex: mutexes.mutex('crud'),
      );

      sync.streamingSync();
      sync.statusUpdates.listen((event) {
        sPort.sendStatusUpdate(event);
      });
      sync.diagnostics.listen((event) {
        sPort.sendDiagnostics(event);
      });
    },
    (error, stack) async {
      // Properly dispose the database if an uncaught error occurs.
      // Unfortunately, this does not handle disposing while the database is opening.
      // This should be rare - any uncaught error is a bug. And in most cases,
      // it should occur after the database is already open.
      await shutdown();
      Error.throwWithStackTrace(error, stack);
    },
  );
}

final class _IsolateSyncHandle implements RemoteStreamingSyncHandle {
  final SyncIsolatePort _syncIsolate;
  final IsolateResultCollection _results;

  @override
  final Stream<String> diagnostics;

  _IsolateSyncHandle(this._syncIsolate, this._results, this.diagnostics);

  @override
  Future<Int64> requestCheckpoint() {
    final pending = _results.createPending<Int64>();
    _syncIsolate.requestCheckpoint(pending.completer);
    return pending.future;
  }
}

/// Forwards connector calls from the sync isolate to the client, along with
/// their abort signals.
final class _ConnectorCalls {
  final IsolateResultCollection _results;
  final SyncClientPort port;
  int _nextAbortToken = 0;

  _ConnectorCalls(this._results, this.port);

  /// Sends a request for a connector call to the client isolate.
  ///
  /// If [abortSignal] completes before we have a response, also asks the client
  /// to abort the call.
  Future<T> abortableCall<T>(
    Future<void> abortSignal,
    void Function(PortCompleter<T> completer, int abortToken) send,
  ) {
    final abortToken = _nextAbortToken++;
    final result = _results.createPending<T>();
    send(result.completer, abortToken);

    var hasResponse = false;
    abortSignal.then((_) {
      if (!hasResponse) port.sendAbortConnectorCall(abortToken);
    });
    return result.future.whenComplete(() => hasResponse = true);
  }
}

final class _ClientPortAuthenticator implements InternalAuthenticator {
  final _ConnectorCalls _calls;

  _ClientPortAuthenticator(this._calls);

  @override
  bool get mightPostCheckpointRequests => true;

  @override
  Future<PowerSyncCredentials?> getCredentialsCached(Future<void> abortSignal) {
    return _calls.abortableCall(
      abortSignal,
      _calls.port.sendGetCredentialsCached,
    );
  }

  @override
  FutureOr<String?> postCheckpointRequest(
    String clientId,
    String requestId,
    Future<void> abortSignal,
  ) {
    return _calls.abortableCall<String?>(abortSignal, (completer, abortToken) {
      _calls.port.sendCustomCheckpointRequest(
        completer,
        abortToken,
        clientId,
        requestId,
      );
    });
  }

  @override
  Future<PowerSyncCredentials?> prefetchCredentials({
    bool invalidate = false,
    required Future<void> abortSignal,
  }) {
    return _calls.abortableCall<PowerSyncCredentials?>(abortSignal, (
      completer,
      abortToken,
    ) {
      _calls.port.sendPrefetchCredentials(completer, abortToken, invalidate);
    });
  }
}

final class _ClientPortUploader implements InternalMutationUploader {
  final _ConnectorCalls _calls;

  _ClientPortUploader(this._calls);

  @override
  Future<void> upload(Future<void> abortSignal) {
    return _calls.abortableCall(abortSignal, _calls.port.sendUploadCrud);
  }
}
