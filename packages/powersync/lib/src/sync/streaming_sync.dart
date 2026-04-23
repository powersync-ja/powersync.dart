import 'dart:async';
import 'dart:convert' as convert;
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:logging/logging.dart';
import 'package:meta/meta.dart';
import 'package:powersync/src/abort_controller.dart';
import 'package:powersync/src/exceptions.dart';
import 'package:powersync/src/log_internal.dart';
import 'package:powersync/src/sync/options.dart';
import 'package:powersync/src/user_agent/user_agent.dart';
import 'package:sqlite_async/sqlite_async.dart';

import '../crud.dart';
import '../platform_specific/platform_specific.dart';
import 'bucket_storage.dart';
import 'instruction.dart';
import 'internal_connector.dart';
import 'mutable_sync_status.dart';
import 'stream_utils.dart';
import 'sync_status.dart';

typedef SubscribedStream = ({String name, String parameters});

abstract interface class StreamingSync {
  Stream<SyncStatus> get statusStream;

  Future<void> streamingSync();

  /// Close any active streams.
  Future<void> abort();

  void updateSubscriptions(List<SubscribedStream> streams);
}

@internal
class StreamingSyncImplementation implements StreamingSync {
  final String schemaJson;
  final BucketStorage adapter;
  final InternalConnector connector;
  final ResolvedSyncOptions options;
  List<SubscribedStream> _activeSubscriptions;

  final Logger logger;

  final Stream<void> crudUpdateTriggerStream;

  // An internal controller which is used to trigger CRUD uploads internally
  // e.g. when reconnecting.
  // This is only a broadcast controller since the `crudLoop` method is public
  // and could potentially be called multiple times externally.
  final StreamController<Null> _internalCrudTriggerController =
      StreamController<Null>.broadcast();

  final http.Client _client;

  final SyncStatusStateStream _state = SyncStatusStateStream();

  AbortController? _abort;

  final Mutex syncMutex, crudMutex;
  Completer<void>? _activeCrudUpload;
  final StreamController<SyncEvent> _nonLineSyncEvents =
      StreamController.broadcast();

  final Map<String, String> _userAgentHeaders;
  String? clientId;

  StreamingSyncImplementation({
    required this.schemaJson,
    required this.adapter,
    required this.connector,
    required this.crudUpdateTriggerStream,
    required this.options,
    required http.Client client,
    List<SubscribedStream> activeSubscriptions = const [],
    Mutex? syncMutex,
    Mutex? crudMutex,
    Logger? logger,

    /// A unique identifier for this streaming sync implementation
    /// A good value is typically the DB file path which it will mutate when syncing.
    String? identifier = "unknown",
  })  : _client = client,
        syncMutex = syncMutex ?? potentiallySharedMutex("sync-$identifier"),
        crudMutex = crudMutex ?? potentiallySharedMutex("crud-$identifier"),
        _userAgentHeaders = userAgentHeaders(),
        logger = logger ?? isolateLogger,
        _activeSubscriptions = activeSubscriptions;

  Duration get _retryDelay => options.retryDelay;

  @override
  Stream<SyncStatus> get statusStream => _state.statusStream;

  @override
  Future<void> abort() async {
    // If streamingSync() hasn't been called yet, _abort will be null.
    if (_abort case final abort?) {
      final future = abort.abort();
      _internalCrudTriggerController.close();

      // If a sync iteration is active, the control flow to abort is:
      //
      //  1. We close the non-line sync event stream here.
      //  2. This emits a done event.
      //  3. `addBroadcastStream` will cancel all source subscriptions in
      //      response to that, and then emit a done event too. If there is an
      //      error while cancelling the stream, it's forwarded by emitting an
      //      error before closing.
      //  4. We break out of the sync loop (either due to an error or because
      //     all resources have been closed correctly).
      //  5. `streamingSync` completes the abort controller, which we await
      //     here.
      await _nonLineSyncEvents.close();

      // Wait for the abort to complete, which also guarantees that no requests
      // are pending.
      await Future.wait([
        future,
        if (_activeCrudUpload case final activeUpload?) activeUpload.future,
      ]);

      _client.close();
      _state.close();
    }
  }

  bool get aborted {
    return _abort?.aborted ?? false;
  }

  @override
  void updateSubscriptions(List<SubscribedStream> streams) {
    _activeSubscriptions = streams;
    if (_nonLineSyncEvents.hasListener) {
      _nonLineSyncEvents.add(HandleChangedSubscriptions(streams));
    }
  }

  @override
  Future<void> streamingSync() async {
    assert(_abort == null);
    final abort = _abort = AbortController();

    try {
      clientId = await adapter.getClientId();
      _crudLoop();
      while (!aborted) {
        var delayNextIteration = false;

        try {
          // Protect sync iterations with exclusivity (if a valid Mutex is provided)
          final (:immediateRestart) = await syncMutex.lock(
            () => _rustStreamingSyncIteration(abort),
            abortTrigger: Future.delayed(_retryDelay),
          );
          delayNextIteration = !immediateRestart;
        } catch (e, stacktrace) {
          if (aborted && e is http.ClientException) {
            // Explicit abort requested - ignore. Example error:
            // ClientException: Connection closed while receiving data, uri=http://localhost:8080/sync/stream
            return;
          }
          delayNextIteration = true;
          final message = _syncErrorMessage(e);
          logger.warning('Sync error: $message', e, stacktrace);

          _state.updateStatus((s) => s.applyDownloadError(e));
        }

        // On error, wait a little before retrying
        // When aborting, don't wait
        if (!aborted && delayNextIteration) {
          await _delayRetry();
        }
      }
    } finally {
      abort.completeAbort();
    }
  }

  Future<void> _crudLoop() async {
    await _uploadAllCrud();

    // Trigger a CRUD upload whenever the upstream trigger fires
    // as-well-as whenever the sync stream reconnects.
    // This has the potential (in rare cases) to affect the crudThrottleTime,
    // but it should not result in excessive uploads since the
    // sync reconnects are also throttled.
    // The stream here is closed on abort.
    await for (var _ in mergeStreams(
        [crudUpdateTriggerStream, _internalCrudTriggerController.stream])) {
      await _uploadAllCrud();
    }
  }

  Future<void> _uploadAllCrud() {
    assert(_activeCrudUpload == null);
    final completer = _activeCrudUpload = Completer();
    return crudMutex.lock(() async {
      // Keep track of the first item in the CRUD queue for the last `uploadCrud` iteration.
      CrudEntry? checkedCrudItem;

      while (true) {
        try {
          // It's possible that an abort or disconnect operation could
          // be followed by a `close` operation. The close would cause these
          // operations, which use the DB, to throw an exception. Breaking the loop
          // here prevents unnecessary potential (caught) exceptions.
          if (aborted) {
            break;
          }
          // This is the first item in the FIFO CRUD queue.
          CrudEntry? nextCrudItem = await adapter.nextCrudItem();
          if (nextCrudItem != null) {
            _state.updateStatus((s) => s.uploading = true);
            if (nextCrudItem.clientId == checkedCrudItem?.clientId) {
              // This will force a higher log level than exceptions which are caught here.
              logger.warning(
                  """Potentially previously uploaded CRUD entries are still present in the upload queue. 
                Make sure to handle uploads and complete CRUD transactions or batches by calling and awaiting their [.complete()] method.
                The next upload iteration will be delayed.""");
              throw Exception(
                  'Delaying due to previously encountered CRUD item.');
            }

            checkedCrudItem = nextCrudItem;
            await connector.uploadCrud();
            _state.updateStatus((s) => s.uploadError = null);
          } else {
            // Uploading is completed
            await adapter.updateLocalTarget(() => getWriteCheckpoint());
            break;
          }
        } catch (e, stacktrace) {
          checkedCrudItem = null;
          logger.warning('Data upload error', e, stacktrace);
          _state.updateStatus((s) => s.applyUploadError(e));
          await _delayRetry();

          if (!_state.status.connected) {
            // Exit the upload loop if the sync stream is no longer connected
            break;
          }
          logger.warning(
              "Caught exception when uploading. Upload will retry after a delay",
              e,
              stacktrace);
        } finally {
          _state.updateStatus((s) => s.uploading = false);
        }
      }
    }, abortTrigger: Future.delayed(_retryDelay)).whenComplete(() {
      if (!aborted) {
        _nonLineSyncEvents.add(const UploadCompleted());
      }

      assert(identical(_activeCrudUpload, completer));
      _activeCrudUpload = null;
      completer.complete();
    });
  }

  Future<String> getWriteCheckpoint() async {
    final credentials = await connector.getCredentialsCached();
    if (credentials == null) {
      throw CredentialsException("Not logged in");
    }
    final uri =
        credentials.endpointUri('write-checkpoint2.json?client_id=$clientId');

    Map<String, String> headers = {
      'Content-Type': 'application/json',
      'Authorization': "Token ${credentials.token}",
      ..._userAgentHeaders
    };

    final response = await _client.get(uri, headers: headers);
    if (response.statusCode == 401) {
      await connector.prefetchCredentials(invalidate: true);
    }
    if (response.statusCode != 200) {
      throw SyncResponseException.fromResponse(response);
    }

    final body = convert.jsonDecode(response.body);
    return body['data']['write_checkpoint'] as String;
  }

  Future<RustSyncIterationResult> _rustStreamingSyncIteration(
      AbortController abortController) async {
    logger.info('Starting Rust sync iteration');
    final response = await _ActiveRustStreamingIteration(this, abortController)
        .syncIteration();
    logger.info(
        'Ending Rust sync iteration. Immediate restart: ${response.immediateRestart}');
    return response;
  }

  Future<http.StreamedResponse?> _postStreamRequest(Object? data,
      {Future<void>? onAbort}) async {
    const ndJson = 'application/x-ndjson';
    const bson = 'application/vnd.powersync.bson-stream';

    final credentials = await connector.getCredentialsCached();
    if (credentials == null) {
      throw CredentialsException('Not logged in');
    }
    final uri = credentials.endpointUri('sync/stream');

    final request = http.AbortableRequest('POST', uri,
        abortTrigger: onAbort ?? _abort!.onAbort);
    request.headers['Content-Type'] = 'application/json';
    request.headers['Authorization'] = "Token ${credentials.token}";
    request.headers['Accept'] = '$bson;q=0.9,$ndJson;q=0.8';
    request.headers.addAll(_userAgentHeaders);

    request.body = convert.jsonEncode(data);

    final res = await _client.send(request);
    if (aborted) {
      return null;
    }

    if (res.statusCode == 401) {
      await connector.prefetchCredentials(invalidate: true);
    }
    if (res.statusCode != 200) {
      throw await SyncResponseException.fromStreamedResponse(res);
    }

    return res;
  }

  /// Delays the standard `retryDelay` Duration, but exits early if
  /// an abort has been requested.
  Future<void> _delayRetry() async {
    await Future.any([Future<void>.delayed(_retryDelay), _abort!.onAbort]);
  }
}

/// Attempt to give a basic summary of the error for cases where the full error
/// is not logged.
String _syncErrorMessage(Object? error) {
  if (error == null) {
    return 'Unknown';
  } else if (error is http.ClientException) {
    return 'Sync service error';
  } else if (error is SyncResponseException) {
    if (error.statusCode == 401) {
      return 'Authorization error';
    } else {
      return 'Sync service error';
    }
  } else if (error is ArgumentError || error is FormatException) {
    return 'Configuration error';
  } else if (error is CredentialsException) {
    return 'Credentials error';
  } else if (error is PowerSyncProtocolException) {
    return 'Protocol error';
  } else {
    return '${error.runtimeType}: $error';
  }
}

typedef BucketDescription = ({
  String name,
  int priority,
});

final class _ActiveRustStreamingIteration {
  final StreamingSyncImplementation sync;
  final AbortController _abortController;

  var _hadSyncLine = false;
  StreamSubscription<void>? _completedUploads;

  _ActiveRustStreamingIteration(this.sync, this._abortController);

  List<Object?> _encodeSubscriptions(List<SubscribedStream> subscriptions) {
    return sync._activeSubscriptions
        .map((s) =>
            {'name': s.name, 'params': convert.json.decode(s.parameters)})
        .toList();
  }

  Future<RustSyncIterationResult> syncIteration() async {
    const defaultResult = (immediateRestart: false);
    Stream<SyncEvent>? events;

    for (final startInstruction in await _startCommand()) {
      switch (startInstruction) {
        case EstablishSyncStream(:final request):
          events = addBroadcast(
            _receiveLines(request),
            sync._nonLineSyncEvents.stream,
          );
        case CloseSyncStream():
          return defaultResult;
        case final NonInterruptingInstruction other:
          await _handleInstruction(other);
      }
    }
    if (events == null) return defaultResult;

    try {
      return await _handleLines(events);
    } finally {
      await _completedUploads?.cancel();
      await _stop();
    }
  }

  Future<Iterable<Instruction>> _startCommand() async {
    return await _invokePowerSyncControl(
      'start',
      convert.json.encode({
        'app_metadata': sync.options.appMetadata,
        'parameters': sync.options.params,
        'schema': convert.json.decode(sync.schemaJson),
        'include_defaults': sync.options.includeDefaultStreams,
        'active_streams': _encodeSubscriptions(sync._activeSubscriptions),
      }),
    );
  }

  Stream<SyncEvent> _receiveLines(Object? data) {
    return streamFromFutureAwaitInCancellation(
            sync._postStreamRequest(data, onAbort: _abortController.onAbort))
        .asyncExpand<SyncEvent>((response) async* {
      if (response == null) {
        return;
      } else {
        yield ConnectionEvent.established;

        final contentType = response.headers['content-type'];
        final isBson = contentType == 'application/vnd.powersync.bson-stream';

        yield* (isBson ? response.stream.bsonDocuments : response.stream.lines)
            .map(ReceivedLine.new);
        yield ConnectionEvent.end;
      }
    });
  }

  Future<RustSyncIterationResult> _handleLines(Stream<SyncEvent> events) async {
    var needsImmediateRestart = false;
    try {
      loop:
      await for (final event in events) {
        if (sync.aborted) {
          break;
        }
        final Iterable<Instruction> instructions;
        switch (event) {
          case ConnectionEvent():
            instructions = await _invokePowerSyncControl(
              'connection',
              event.name,
            );
          case ReceivedLine(line: final Uint8List line):
            _triggerCrudUploadOnFirstLine();
            instructions = await _invokePowerSyncControl('line_binary', line);
          case ReceivedLine(line: final line as String):
            _triggerCrudUploadOnFirstLine();
            instructions = await _invokePowerSyncControl('line_text', line);
          case UploadCompleted():
            instructions = await _invokePowerSyncControl('completed_upload');
          case TokenRefreshComplete():
            instructions = await _invokePowerSyncControl('refreshed_token');
          case HandleChangedSubscriptions(:final currentSubscriptions):
            instructions = await _invokePowerSyncControl(
              'update_subscriptions',
              convert.json.encode(_encodeSubscriptions(currentSubscriptions)),
            );
        }

        for (final instruction in instructions) {
          switch (instruction) {
            case EstablishSyncStream():
              sync.logger.warning(
                'Received EstablishSyncStream connection while already '
                'connected.',
              );
            case CloseSyncStream(:final hideDisconnect):
              needsImmediateRestart = hideDisconnect;
              break loop;
            case final NonInterruptingInstruction other:
              await _handleInstruction(other);
          }
        }
      }
    } on http.RequestAbortedException {
      // Unlike a regular cancellation, cancelling via the abort controller
      // emits an error. We did mean to just cancel the stream, so we can
      // safely ignore that.
      if (sync.aborted) {
        // ignore
      } else {
        rethrow;
      }
    }

    return (immediateRestart: needsImmediateRestart);
  }

  /// Triggers a local CRUD upload when the first sync line has been received.
  ///
  /// This allows uploading local changes that have been made while offline or
  /// disconnected.
  void _triggerCrudUploadOnFirstLine() {
    if (!_hadSyncLine) {
      sync._internalCrudTriggerController.add(null);
      _hadSyncLine = true;
    }
  }

  Future<void> _stop() async {
    final instructions = await _invokePowerSyncControl('stop');
    for (final instruction in instructions) {
      // We don't need to handle interrupting instructions since we're
      // unconditionally ending the sync iteration at this point.
      if (instruction is NonInterruptingInstruction) {
        await _handleInstruction(instruction);
      }
    }
  }

  Future<Iterable<Instruction>> _invokePowerSyncControl(String operation,
      [Object? payload]) async {
    final rawResponse = await sync.adapter.control(operation, payload);
    final instructions = convert.json.decode(rawResponse) as List;

    return instructions.cast<Map<String, Object?>>().map(Instruction.fromJson);
  }

  Future<void> _handleInstruction(
      NonInterruptingInstruction instruction) async {
    switch (instruction) {
      case LogLine(:final severity, :final line):
        sync.logger.log(
            switch (severity) {
              'DEBUG' => Level.FINE,
              'INFO' => Level.INFO,
              _ => Level.WARNING,
            },
            line);
      case UpdateSyncStatus(:final status):
        sync._state.updateStatus((m) => m.applyFromCore(status));
      case FetchCredentials(:final didExpire):
        if (didExpire) {
          await sync.connector.prefetchCredentials(invalidate: true);
        } else {
          sync.connector.prefetchCredentials().then((_) {
            if (!sync.aborted) {
              sync._nonLineSyncEvents.add(const TokenRefreshComplete());
            }
          }, onError: (Object e, StackTrace s) {
            sync.logger.warning('Could not prefetch credentials', e, s);
          });
        }
      case FlushFileSystem():
        await sync.adapter.flushFileSystem();
      case DidCompleteSync():
        sync._state.updateStatus((m) => m.downloadError = null);
      case UnknownSyncInstruction(:final source):
        sync.logger.warning('Unknown instruction: $source');
    }
  }
}

typedef RustSyncIterationResult = ({bool immediateRestart});

sealed class SyncEvent {}

enum ConnectionEvent implements SyncEvent {
  established,
  end,
}

final class ReceivedLine implements SyncEvent {
  final Object /* String|Uint8List|StreamingSyncLine */ line;

  const ReceivedLine(this.line);
}

final class UploadCompleted implements SyncEvent {
  const UploadCompleted();
}

final class TokenRefreshComplete implements SyncEvent {
  const TokenRefreshComplete();
}

final class HandleChangedSubscriptions implements SyncEvent {
  final List<SubscribedStream> currentSubscriptions;

  HandleChangedSubscriptions(this.currentSubscriptions);
}
