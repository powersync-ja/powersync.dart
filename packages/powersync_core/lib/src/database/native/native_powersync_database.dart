import 'dart:async';
import 'dart:convert';
import 'dart:isolate';
import 'package:meta/meta.dart';

import 'package:http/http.dart' as http;
import 'package:logging/logging.dart';
import 'package:powersync_core/src/abort_controller.dart';
import 'package:powersync_core/src/database/native/remote_mutex.dart';
import 'package:powersync_core/src/sync/bucket_storage.dart';
import 'package:powersync_core/src/connector.dart';
import 'package:powersync_core/src/database/powersync_database.dart';
import 'package:powersync_core/src/isolate_completer.dart';
import 'package:powersync_core/src/log_internal.dart';
import 'package:powersync_core/src/sync/internal_connector.dart';
import 'package:powersync_core/src/sync/options.dart';
import 'package:powersync_core/src/sync/streaming_sync.dart';
import 'package:powersync_core/src/sync/sync_status.dart';
import 'package:sqlite_async/sqlite_async.dart';

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
    required Stream<List<({String name, String parameters})>> activeStreams,
    required AbortController abort,
    required Zone asyncWorkZone,
  }) async {
    bool triedSpawningIsolate = false;
    StreamSubscription<UpdateNotification>? crudUpdateSubscription;
    StreamSubscription<void>? activeStreamsSubscription;
    final receiveMessages = ReceivePort();
    final receiveUnhandledErrors = ReceivePort();
    final receiveExit = ReceivePort();
    final mutexServer = MutexServer({
      'sync': group.syncMutex,
      'crud': group.crudMutex,
    });

    SendPort? initPort;
    final hasInitPort = Completer<void>();
    final receivedIsolateExit = Completer<void>();

    Future<void> waitForShutdown() async {
      // Only complete the abortion signal after the isolate shuts down. This
      // ensures absolutely no trace of this sync iteration remains.
      if (triedSpawningIsolate) {
        await receivedIsolateExit.future;
      }

      // Cleanup
      crudUpdateSubscription?.cancel();
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
      initPort?.send(['close']);
      await waitForShutdown();
    }

    Future<void> handleMessage(Object? data) async {
      if (data is List) {
        String action = data[0] as String;
        if (action == "getCredentialsCached") {
          await (data[1] as PortCompleter).handle(() async {
            final token = await connector.getCredentialsCached();
            logger.fine('Credentials: $token');
            return token;
          });
        } else if (action == "prefetchCredentials") {
          logger.fine('Refreshing credentials');
          final invalidate = data[2] as bool;

          await (data[1] as PortCompleter).handle(() async {
            if (invalidate) {
              connector.invalidateCredentials();
            }
            return await connector.prefetchCredentials();
          });
        } else if (action == 'init') {
          final port = initPort = data[1] as SendPort;
          hasInitPort.complete();
          var crudStream = database
              .onChange(['ps_crud'], throttle: options.crudThrottleTime);
          crudUpdateSubscription = crudStream.listen((event) {
            port.send(['update']);
          });

          activeStreamsSubscription = activeStreams.listen((streams) {
            port.send(['changed_subscriptions', streams]);
          });
        } else if (action == 'uploadCrud') {
          await (data[1] as PortCompleter).handle(() async {
            await connector.uploadData(this);
          });
        } else if (action == 'status') {
          final SyncStatus status = data[1] as SyncStatus;
          setStatus(status);
        } else if (action == 'log') {
          LogRecord record = data[1] as LogRecord;
          logger.log(
              record.level, record.message, record.error, record.stackTrace);
        } else if (action == 'mutex:acquire') {
          mutexServer.acquireRequest(
              initPort!, data[1] as String, data[2] as int);
        } else if (action == 'mutex:release') {
          mutexServer.releaseRequest(data[1] as int);
        }
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
        receiveMessages.sendPort,
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

    abort.onAbort.whenComplete(close);

    // Automatically complete the abort controller once the isolate exits.
    unawaited(waitForShutdown());
  }
}

class _PowerSyncDatabaseIsolateArgs {
  final SendPort sPort;
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
  StreamController<String> crudUpdateController = StreamController.broadcast();

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

        crudUpdateController.close();
        database.close();

        rPort.close();

        // TODO: If we closed our resources properly, this wouldn't be necessary...
        Isolate.current.kill();
      }));
    }

    return shutdownCompleter.future;
  }

  rPort.listen((message) async {
    if (message is List) {
      String action = message[0] as String;
      if (action == 'update') {
        if (!crudUpdateController.isClosed) {
          crudUpdateController.add('update');
        }
      } else if (action == 'close') {
        await shutdown();
      } else if (action == 'changed_subscriptions') {
        openedStreamingSync
            ?.updateSubscriptions(message[1] as List<SubscribedStream>);
      } else if (action == 'mutex:granted') {
        mutexes.markGranted(message[1] as int);
      }
    }
  });
  sPort.send(['init', rPort.sendPort]);

  // Is there a way to avoid the overhead if logging is not enabled?
  // This only takes effect in this isolate.
  isolateLogger.level = Level.ALL;
  isolateLogger.onRecord.listen((record) {
    var copy = LogRecord(record.level, record.message, record.loggerName,
        record.error, record.stackTrace);
    sPort.send(['log', copy]);
  });

  Future<PowerSyncCredentials?> getCredentialsCached() async {
    final r = IsolateResult<PowerSyncCredentials?>();
    sPort.send(['getCredentialsCached', r.completer]);
    return r.future;
  }

  Future<PowerSyncCredentials?> prefetchCredentials(
      {required bool invalidate}) async {
    final r = IsolateResult<PowerSyncCredentials?>();
    sPort.send(['prefetchCredentials', r.completer, invalidate]);
    return r.future;
  }

  Future<void> uploadCrud() async {
    final r = IsolateResult<void>();
    sPort.send(['uploadCrud', r.completer]);
    return r.future;
  }

  runZonedGuarded(() async {
    final storage = BucketStorage(database);
    final sync = StreamingSyncImplementation(
      adapter: storage,
      schemaJson: args.schemaJson,
      connector: InternalConnector(
        getCredentialsCached: getCredentialsCached,
        prefetchCredentials: prefetchCredentials,
        uploadCrud: uploadCrud,
      ),
      crudUpdateTriggerStream: crudUpdateController.stream,
      options: args.options,
      client: http.Client(),
      syncMutex: mutexes.mutex('sync'),
      crudMutex: mutexes.mutex('crud'),
    );
    openedStreamingSync = sync;
    sync.streamingSync();
    sync.statusStream.listen((event) {
      sPort.send(['status', event]);
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
