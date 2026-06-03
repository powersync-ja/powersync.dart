import 'dart:async';
import 'dart:convert';
import 'dart:isolate';
import 'package:meta/meta.dart';

import 'package:logging/logging.dart';
import 'package:powersync/src/abort_controller.dart';
import 'package:powersync/src/sync/bucket_storage.dart';
import 'package:powersync/src/connector.dart';
import 'package:powersync/src/database/powersync_database.dart';
import 'package:powersync/src/isolate_completer.dart';
import 'package:powersync/src/log_internal.dart';
import 'package:powersync/src/sync/internal_connector.dart';
import 'package:powersync/src/sync/options.dart';
import 'package:powersync/src/sync/streaming_sync.dart';
import 'package:powersync/src/sync/sync_status.dart';
import 'package:sqlite_async/sqlite_async.dart';

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
  });

  @override
  @internal
  Future<void> connectInternal({
    required PowerSyncBackendConnector connector,
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
    final receiveExit = ReceivePort();
    final mutexServer = MutexServer({
      'sync': group.syncMutex,
      'crud': group.crudMutex,
    });

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
      activeStreamsSubscription?.cancel();
      receiveMessages.close();
      receiveUnhandledErrors.close();
      receiveExit.close();
      mutexServer.handleChildIsolateExit();

      // Clear status apart from lastSyncedAt
      setStatus(SyncStatus(lastSyncedAt: currentStatus.lastSyncedAt));
      abort.completeAbort();
    }

    Future<void> close() async {
      initPort?.sendClose();
      await waitForShutdown();
    }

    Future<void> handleMessage(Object? data) async {
      final (type, payload) = data as SyncIsolateToClientMessage;
      switch (type) {
        case SyncIsolateToClientMessageType.getCredentialsCached:
          await (payload as PortCompleter).handle(() async {
            final token = await connector.getCredentialsCached();
            logger.fine('Credentials: $token');
            return token;
          });
        case SyncIsolateToClientMessageType.prefetchCredentials:
          logger.fine('Refreshing credentials');
          final (completer, invalidate) =
              payload as (PortCompleter<PowerSyncCredentials?>, bool);

          await completer.handle(() async {
            if (invalidate) {
              connector.invalidateCredentials();
            }
            return await connector.prefetchCredentials();
          });
        case SyncIsolateToClientMessageType.init:
          final port = initPort = SyncIsolatePort(payload as SendPort);
          hasInitPort.complete();

          activeStreamsSubscription = activeStreams.listen((streams) {
            port.sendChangedSubscriptions(streams);
          });
        case SyncIsolateToClientMessageType.uploadCrud:
          await (payload as PortCompleter).handle(() async {
            await connector.uploadData(this);
          });
        case SyncIsolateToClientMessageType.status:
          setStatus(payload as SyncStatus);
        case SyncIsolateToClientMessageType.log:
          LogRecord record = payload as LogRecord;
          logger.log(
              record.level, record.message, record.error, record.stackTrace);
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
      return waitForShutdown();
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
      ),
      debugName: 'Sync ${database.openFactory.path}',
      onError: receiveUnhandledErrors.sendPort,
      errorsAreFatal: true,
      onExit: receiveExit.sendPort,
    );
    await hasInitPort.future;

    // Automatically complete the abort controller once the isolate exits.
    unawaited(Future.any([abort.onAbort, receivedIsolateExit.future])
        .whenComplete(close));
  }
}

class _PowerSyncDatabaseIsolateArgs {
  final SyncClientPort sPort;
  final String databaseName;
  final ResolvedSyncOptions options;
  final String schemaJson;

  _PowerSyncDatabaseIsolateArgs(
    this.sPort,
    this.databaseName,
    this.options,
    this.schemaJson,
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
      shutdownCompleter.complete(Future(() async {
        await openedStreamingSync?.abort();
        await database.close();

        rPort.close();
        results.close();
      }));
    }

    return shutdownCompleter.future;
  }

  rPort.listen((message) async {
    final (type, payload) = message as ClientToSyncIsolateMessage;
    switch (type) {
      case ClientToSyncIsolateMessageType.close:
        shutdown();
      case ClientToSyncIsolateMessageType.changedSubscriptions:
        openedStreamingSync
            ?.updateSubscriptions(payload as List<SubscribedStream>);
      case ClientToSyncIsolateMessageType.mutexGranted:
        mutexes.markGranted(payload as int);
    }
  });
  sPort.sendInit(rPort.sendPort);

  // Is there a way to avoid the overhead if logging is not enabled?
  // This only takes effect in this isolate.
  isolateLogger.level = Level.ALL;
  isolateLogger.onRecord.listen((record) {
    var copy = LogRecord(record.level, record.message, record.loggerName,
        record.error, record.stackTrace);
    sPort.sendLog(copy);
  });

  Future<PowerSyncCredentials?> getCredentialsCached() async {
    final r = results.createPending<PowerSyncCredentials?>();
    sPort.sendGetCredentialsCached(r.completer);
    return r.future;
  }

  Future<PowerSyncCredentials?> prefetchCredentials(
      {required bool invalidate}) async {
    final r = results.createPending<PowerSyncCredentials?>();
    sPort.sendPrefetchCredentials(r.completer, invalidate);
    return r.future;
  }

  Future<void> uploadCrud() async {
    final r = results.createPending<void>();
    sPort.sendUploadCrud(r.completer);
    return r.future;
  }

  runZonedGuarded(() async {
    final storage = BucketStorage(database);
    final sync = openedStreamingSync = StreamingSyncImplementation(
      adapter: storage,
      schemaJson: args.schemaJson,
      connector: InternalConnector(
        getCredentialsCached: getCredentialsCached,
        prefetchCredentials: prefetchCredentials,
        uploadCrud: uploadCrud,
      ),
      crudUpdateTriggerStream: database
          .onChange(['ps_crud'], throttle: args.options.crudThrottleTime),
      options: args.options,
      syncMutex: mutexes.mutex('sync'),
      crudMutex: mutexes.mutex('crud'),
    );

    sync.streamingSync();
    sync.statusStream.listen((event) {
      sPort.sendStatus(event);
    });
  }, (error, stack) async {
    // Properly dispose the database if an uncaught error occurs.
    // Unfortunately, this does not handle disposing while the database is opening.
    // This should be rare - any uncaught error is a bug. And in most cases,
    // it should occur after the database is already open.
    await shutdown();
    Error.throwWithStackTrace(error, stack);
  });
}
