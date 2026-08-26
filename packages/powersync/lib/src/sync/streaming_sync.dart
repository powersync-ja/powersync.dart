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

import '../connector.dart';
import '../crud.dart';
import '../platform_specific/int64.dart';
import '../platform_specific/platform_specific.dart';
import 'bucket_storage.dart';
import 'checkpoint_request.dart' as checkpoint;
import 'checkpoint_state.dart';
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
  final StreamController<Null> _internalCrudTriggerController =
      StreamController<Null>();

  final http.Client _client;

  final SyncStatusStateStream _state = SyncStatusStateStream();
  final CheckpointStateSignals _checkpointState = CheckpointStateSignals();

  AbortController? _abort;

  final Mutex syncMutex, crudMutex;
  final StreamController<SyncEvent> _nonLineSyncEvents =
      StreamController.broadcast();

  final Map<String, String> _userAgentHeaders;
  String? _clientId;

  StreamingSyncImplementation({
    required this.schemaJson,
    required this.adapter,
    required this.connector,
    required this.crudUpdateTriggerStream,
    required this.options,
    List<SubscribedStream> activeSubscriptions = const [],
    Mutex? syncMutex,
    Mutex? crudMutex,
    Logger? logger,

    /// A unique identifier for this streaming sync implementation
    /// A good value is typically the DB file path which it will mutate when syncing.
    String? identifier = "unknown",
  }) : _client = options.createHttpClient(),
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
      await (
        abort.abort(),
        _internalCrudTriggerController.close(),
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
        _nonLineSyncEvents.close(),
      ).wait;
    }

    _client.close();
    _state.close();
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
      await _resolveClientId();

      final crudLoop = _crudLoop(abort).onError((
        Object error,
        StackTrace stackTrace,
      ) {
        if (abort.isAbortException(error)) return;

        logger.warning('Error in crud upload loop', error, stackTrace);
      });

      await (
        crudLoop,
        _downloadLoop(abort),
        _repostUnacknowledgedCheckpointRequests(abort),
      ).wait;
    } finally {
      _checkpointState.disconnect();
      abort.completeAbort();
    }
  }

  Future<String> _resolveClientId() async {
    return (_clientId ??= await adapter.getClientId());
  }

  Future<void> _downloadLoop(AbortController abort) async {
    while (!abort.aborted) {
      var delayNextIteration = false;

      try {
        // Protect sync iterations with exclusivity (if a valid Mutex is provided)
        final (:immediateRestart) = await syncMutex.lock(
          () => _rustStreamingSyncIteration(abort),
          abortTrigger: _delayRetry(abort),
        );
        delayNextIteration = !immediateRestart;
      } catch (e, stacktrace) {
        if (abort.isAbortException(e)) {
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
      if (!abort.aborted && delayNextIteration) {
        await abort.scoped((onAbort) {
          final (retryDelay, completeEarly) = _delayOr(_retryDelay);
          onAbort.whenComplete(completeEarly);
          _checkpointState.waitForCheckpointWaiter().whenComplete(
            completeEarly,
          );

          return retryDelay;
        });
      }
    }
  }

  Future<void> _crudLoop(AbortController abort) async {
    // Trigger a CRUD upload whenever the upstream trigger fires
    // as-well-as whenever the sync stream reconnects.
    // This has the potential (in rare cases) to affect the crudThrottleTime,
    // but it should not result in excessive uploads since the
    // sync reconnects are also throttled.
    // The stream here is closed on abort.
    await for (var _ in mergeStreams([
      crudUpdateTriggerStream,
      _internalCrudTriggerController.stream,
    ])) {
      await crudMutex.lock(
        () => _crudUploadIteration(abort),
        abortTrigger: _delayRetry(abort),
      );
    }
  }

  Future<void> _crudUploadIteration(AbortController abort) async {
    // Keep track of the first item in the CRUD queue for the last `uploadCrud` iteration.
    CrudEntry? checkedCrudItem;

    while (!abort.aborted) {
      var didCompleteUpload = false;

      try {
        // This is the first item in the FIFO CRUD queue.
        CrudEntry? nextCrudItem = await adapter.nextCrudItem();
        if (nextCrudItem != null) {
          _state.updateStatus((s) => s.uploading = true);
          if (nextCrudItem.clientId == checkedCrudItem?.clientId) {
            // This will force a higher log level than exceptions which are caught here.
            logger.warning(
              """Potentially previously uploaded CRUD entries are still present in the upload queue. 
                Make sure to handle uploads and complete CRUD transactions or batches by calling and awaiting their [.complete()] method.
                The next upload iteration will be delayed.""",
            );
            throw Exception(
              'Delaying due to previously encountered CRUD item.',
            );
          }

          checkedCrudItem = nextCrudItem;
          await connector.uploadCrud();
          _state.updateStatus((s) => s.uploadError = null);
        } else {
          // Uploading is completed
          didCompleteUpload = await adapter.updateTargetCheckpointRequest(() {
            if (options.checkpointMode is LegacyCheckpointMode) {
              return _getLegacyWriteCheckpoint(abort);
            } else {
              return _requestNextCheckpointFromService(abort);
            }
          });
          break;
        }
      } catch (e, stacktrace) {
        checkedCrudItem = null;
        if (abort.isAbortException(e)) {
          return;
        }

        logger.warning('Data upload error', e, stacktrace);
        _state.updateStatus((s) => s.applyUploadError(e));
        await _delayRetry(abort);

        if (!_state.status.connected) {
          // Exit the upload loop if the sync stream is no longer connected
          break;
        }
        logger.warning(
          "Caught exception when uploading. Upload will retry after a delay",
          e,
          stacktrace,
        );
      } finally {
        _state.updateStatus((s) => s.uploading = false);

        if (!abort.aborted && didCompleteUpload) {
          _nonLineSyncEvents.add(const UploadCompleted());
        }
      }
    }
  }

  void _applyCommonHeaders(
    http.Request request,
    PowerSyncCredentials credentials,
  ) {
    request.headers['Authorization'] = "Token ${credentials.token}";
    request.headers.addAll(_userAgentHeaders);
  }

  Future<String> _requestNextCheckpointFromService(AbortController abort) {
    return abort.scoped((abortTrigger) async {
      await _checkpointState.waitForCheckpointRequestsReady(
        abort: abortTrigger,
      );

      final nextCheckpointRequestId = await adapter.writeTransaction(
        onAbort: abortTrigger,
        (tx) => tx.nextCheckpointRequestId(),
      );
      return await _requestCheckpointFromService(
        checkpointRequest: nextCheckpointRequestId,
        abortTrigger: abortTrigger,
      );
    });
  }

  Future<String> _requestCheckpointFromService({
    required String checkpointRequest,
    required Future<void> abortTrigger,
    String? clientId,
  }) async {
    clientId ??= await _resolveClientId();

    // First, check if we can use a custom checkpoint request implementation.
    if (await connector.postCheckpointRequest(clientId, checkpointRequest)
        case final customResponse?) {
      return customResponse;
    }

    final credentials = await connector.getCredentialsCached();
    if (credentials == null) {
      throw CredentialsException("Not logged in");
    }
    final uri = credentials.endpointUri('sync/checkpoint-request');

    final request = http.AbortableRequest(
      'POST',
      uri,
      abortTrigger: abortTrigger,
    );
    request.body = convert.jsonEncode({
      'client_id': clientId,
      'checkpoint_request_id': checkpointRequest,
    });
    _applyCommonHeaders(request, credentials);
    request.headers['Accept'] = 'application/json';
    request.headers['Content-Type'] = 'application/json';
    final response = await http.Response.fromStream(
      await _client.send(request),
    );

    if (response.statusCode == 401) {
      await connector.prefetchCredentials(invalidate: true);
    }
    if (response.statusCode == 404) {
      throw checkpoint.instanceNotSupported;
    }
    if (response.statusCode != 200) {
      throw SyncResponseException.fromResponse(response);
    }

    final body = convert.jsonDecode(response.body);
    return body['data']['checkpoint_request_id'] as String;
  }

  Future<String> _getLegacyWriteCheckpoint(AbortController abort) async {
    final credentials = await connector.getCredentialsCached();
    if (credentials == null) {
      throw CredentialsException("Not logged in");
    }
    final uri = credentials.endpointUri(
      'write-checkpoint2.json?client_id=${await _resolveClientId()}',
    );

    final response = await abort.scoped((onAbort) async {
      final request = http.AbortableRequest('GET', uri, abortTrigger: onAbort);
      _applyCommonHeaders(request, credentials);
      request.headers['Accept'] = 'application/json';

      return await http.Response.fromStream(await _client.send(request));
    });

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
    AbortController abortController,
  ) async {
    logger.info('Starting Rust sync iteration');
    final response = await _ActiveRustStreamingIteration(
      this,
      abortController,
    ).syncIteration();
    logger.info(
      'Ending Rust sync iteration. Immediate restart: ${response.immediateRestart}',
    );
    return response;
  }

  Future<http.StreamedResponse> _postStreamRequest(
    Object? data, {
    required Future<void> onAbort,
  }) async {
    const ndJson = 'application/x-ndjson';
    const bson = 'application/vnd.powersync.bson-stream';

    final credentials = await connector.getCredentialsCached();
    if (credentials == null) {
      throw CredentialsException('Not logged in');
    }
    final uri = credentials.endpointUri('sync/stream');

    final request = http.AbortableRequest('POST', uri, abortTrigger: onAbort);
    _applyCommonHeaders(request, credentials);
    request.headers['Content-Type'] = 'application/json';
    request.headers['Accept'] = '$bson;q=0.9,$ndJson;q=0.8';

    request.body = convert.jsonEncode(data);

    final res = await _client.send(request);

    if (res.statusCode == 401) {
      await connector.prefetchCredentials(invalidate: true);
    }
    if (res.statusCode != 200) {
      throw await SyncResponseException.fromStreamedResponse(res);
    }

    return res;
  }

  /// Watches the current checkpoint request i to re-request it if we take too
  /// long to receive it.
  ///
  /// This does not require navigator locks: It waits for checkpoints to be
  /// seeded, which can only happen in the context of a download loop.
  ///
  /// Note that requesting checkpoints with ids the service has already seen is
  /// a cheap no-op.
  Future<void> _repostUnacknowledgedCheckpointRequests(
    AbortController abort,
  ) async {
    final Duration retryDelay;
    switch (options.checkpointMode) {
      case RequestsCheckpointMode(retryDelay: final delay):
        retryDelay = delay;
      default:
        return;
    }

    while (!abort.aborted) {
      try {
        await abort.scoped((abortSignal) {
          return _repostCurrentCheckpointRequestAfterDelay(
            retryDelay,
            abortSignal,
          );
        });
      } catch (e, s) {
        if (abort.aborted) return;

        logger.warning('Error retrying checkpoint request', e, s);
        await _delayRetry(abort, retryDelay);
      }
    }
  }

  Future<void> _repostCurrentCheckpointRequestAfterDelay(
    Duration retryDelay,
    Future<void> abortSignal,
  ) async {
    Future<Int64?> currentCheckpointRequestId() {
      return adapter.writeTransaction(onAbort: abortSignal, (tx) async {
        final textRequestId = await tx.currentCheckpointRequestId();
        return textRequestId == null ? null : Int64.parse(textRequestId);
      });
    }

    await _checkpointState.waitForCheckpointRequestsReady(
      abort: abortSignal,
      wakeDownloadLoop: false,
    );

    final requestId = await currentCheckpointRequestId();
    // Give the request some time to sync.
    {
      final (delay, complete) = _delayOr(retryDelay);
      abortSignal.whenComplete(complete);
      await delay;
    }

    // If a new request was made, reset the timer.
    if (requestId == null || requestId != await currentCheckpointRequestId()) {
      return;
    }

    // If the request was applied, we don't need to retry.
    if (_state.status.lastAppliedCheckpointRequestId case final lastApplied?
        when lastApplied >= requestId) {
      return;
    }

    // Make sure we're online and ready before making the request.
    await _checkpointState.waitForCheckpointRequestsReady(
      abort: abortSignal,
      wakeDownloadLoop: false,
    );

    // It's safe if this request races with a new one. The service will
    // reject it.
    logger.fine('Retry checkpoint request $requestId');
    await _requestCheckpointFromService(
      checkpointRequest: requestId.toString(),
      abortTrigger: abortSignal,
    );
  }

  /// Delays for [duration] or [_retryDelay], but exits early if an abort has
  /// been requested.
  Future<void> _delayRetry(AbortController abort, [Duration? duration]) {
    return abort.scoped((onAbort) {
      final (future, complete) = _delayOr(duration ?? _retryDelay);
      onAbort.whenComplete(complete);
      return future;
    });
  }
}

/// Returns a future that completes after the [delay] or when the returned
/// function is called.
(Future<void>, void Function()) _delayOr(Duration delay) {
  final completer = Completer<void>.sync();
  Timer? timer;

  void complete() {
    if (!completer.isCompleted) {
      timer?.cancel();
      timer = null;
      completer.complete();
    }
  }

  timer = Timer(delay, complete);
  return (completer.future, complete);
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

typedef BucketDescription = ({String name, int priority});

final class _ActiveRustStreamingIteration {
  final StreamingSyncImplementation sync;
  final AbortController _abortController;

  var _hadSyncLine = false;

  _ActiveRustStreamingIteration(this.sync, this._abortController);

  bool get _aborted => _abortController.aborted;

  List<Object?> _encodeSubscriptions(List<SubscribedStream> subscriptions) {
    return sync._activeSubscriptions
        .map(
          (s) => {'name': s.name, 'params': convert.json.decode(s.parameters)},
        )
        .toList();
  }

  Future<RustSyncIterationResult> syncIteration() {
    const defaultResult = (immediateRestart: false);
    return _abortController.scoped((onAbort) async {
      Stream<SyncEvent>? events;
      AbortController? checkpointSeed;

      for (final startInstruction in await _startCommand()) {
        switch (startInstruction) {
          case EstablishSyncStream(:final request, :final checkpointRequest):
            events = addBroadcast(
              _receiveLines(request, onAbort),
              sync._nonLineSyncEvents.stream,
            );

            if (checkpointRequest != null) {
              final nested = checkpointSeed = AbortController();

              _seedCheckpointRequests(checkpointRequest, nested);
            }
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
        await checkpointSeed?.abort();

        sync._checkpointState.downloadIterationEnded();
        await _stop();
      }
    });
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
        'checkpoint_mode': sync.options.checkpointMode is RequestsCheckpointMode
            ? 'requests'
            : 'legacy',
      }),
    );
  }

  void _seedCheckpointRequests(
    CheckpointRequestPayload payload,
    AbortController abort,
  ) async {
    try {
      final seed = await sync._requestCheckpointFromService(
        checkpointRequest: payload.checkpointRequestId,
        abortTrigger: abort.onAbort,
        clientId: payload.clientId,
      );

      await sync.adapter.writeTransaction(
        (tx) => tx.seedCheckpointRequestId(seed),
        onAbort: abort.onAbort,
      );

      sync._checkpointState.markCheckpointsReady();
    } catch (e, s) {
      // If this was aborted, syncIteration() is about to reset the state
      // anyway.
      if (!abort.aborted) {
        sync._nonLineSyncEvents.add(CheckpointSeedFailed(e, s));

        sync._checkpointState.markCheckpointsFailed(e, s);
      }
    } finally {
      abort.completeAbort();
    }
  }

  Stream<SyncEvent> _receiveLines(Object? data, Future<void> onAbort) {
    return streamFromFutureAwaitInCancellation(
      sync._postStreamRequest(data, onAbort: onAbort),
    ).asyncExpand<SyncEvent>((response) async* {
      yield ConnectionEvent.established;

      final contentType = response.headers['content-type'];
      final isBson = contentType == 'application/vnd.powersync.bson-stream';

      yield* (isBson ? response.stream.bsonDocuments : response.stream.lines)
          .map(ReceivedLine.new);
      yield ConnectionEvent.end;
    });
  }

  Future<RustSyncIterationResult> _handleLines(Stream<SyncEvent> events) async {
    var needsImmediateRestart = false;
    try {
      loop:
      await for (final event in events) {
        if (_aborted) {
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
          case CheckpointSeedFailed(:final error, :final trace):
            Error.throwWithStackTrace(error, trace);
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
      if (_aborted) {
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

  Future<Iterable<Instruction>> _invokePowerSyncControl(
    String operation, [
    Object? payload,
  ]) async {
    final rawResponse = await sync.adapter.control(operation, payload);
    final instructions = convert.json.decode(rawResponse) as List;

    return instructions.cast<Map<String, Object?>>().map(Instruction.fromJson);
  }

  Future<void> _handleInstruction(
    NonInterruptingInstruction instruction,
  ) async {
    switch (instruction) {
      case LogLine(:final severity, :final line):
        sync.logger.log(switch (severity) {
          'DEBUG' => Level.FINE,
          'INFO' => Level.INFO,
          _ => Level.WARNING,
        }, line);
      case UpdateSyncStatus(:final status):
        sync._state.updateStatus((m) => m.applyFromCore(status));
      case FetchCredentials(:final didExpire):
        if (didExpire) {
          await sync.connector.prefetchCredentials(invalidate: true);
        } else {
          sync.connector.prefetchCredentials().then(
            (_) {
              if (!_aborted) {
                sync._nonLineSyncEvents.add(const TokenRefreshComplete());
              }
            },
            onError: (Object e, StackTrace s) {
              sync.logger.warning('Could not prefetch credentials', e, s);
            },
          );
        }
      case DidCompleteSync():
        sync._state.updateStatus((m) => m.downloadError = null);
      case UnknownSyncInstruction(:final source):
        sync.logger.warning('Unknown instruction: $source');
    }
  }
}

typedef RustSyncIterationResult = ({bool immediateRestart});

sealed class SyncEvent {}

enum ConnectionEvent implements SyncEvent { established, end }

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

final class CheckpointSeedFailed implements SyncEvent {
  final Object error;
  final StackTrace trace;

  CheckpointSeedFailed(this.error, this.trace);
}

extension on AbortController {
  bool isAbortException(Object e) {
    if (!aborted) return false;

    return e is http.ClientException || e is AbortException;
  }
}
