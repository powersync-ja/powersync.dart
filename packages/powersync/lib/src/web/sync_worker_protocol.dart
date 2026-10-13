import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:http/http.dart';
import 'package:logging/logging.dart';
import 'package:meta/meta.dart';
import 'package:powersync/src/schema.dart';
import 'package:powersync/src/sync/options.dart';
import 'package:web/web.dart' hide HttpRequest, Client;

import '../connector.dart';
import '../log.dart';
import '../platform_specific/web.dart';
import '../sync/instruction.dart';
import '../sync/status_update.dart';
import '../sync/internal_connector.dart';
import '../sync/streaming_sync.dart';
import 'http/protocol.dart';
import 'http/server.dart';

/// Names used in [SyncWorkerMessage]
enum SyncWorkerMessageType {
  ping,

  /// Sent from client to the sync worker to request the synchronization
  /// starting.
  /// If parameters change, the sync worker reconnects.
  startSynchronization,

  /// Update the active subscriptions that this client is interested in.
  updateSubscriptions,

  /// The [SyncWorkerMessage.payload] for the request is a numeric id, the
  /// response can be anything (void).
  /// This disconnects immediately, even if other clients are still open.
  abortSynchronization,

  /// Sent from the sync worker to the client when it needs an endpoint to
  /// connect to to start the synchronization.
  ///
  /// [SyncWorkerMessage.payload] is a numeric request id, the response sends
  /// a [WebEndpoint].
  requestEndpoint,

  /// Invoke the `uploadCrud`, `fetchCredentials` and `getCredentialsCached`
  /// methods on the client.
  ///
  /// For requests, the [SyncWorkerMessage.payload] is a numeric request id.
  /// The response sends either a [SerializedCredentials] object or an empty
  /// object for uploads.
  uploadCrud,

  /// Invoke [CustomCheckpointRequestConnector.postCheckpointRequest].
  ///
  /// For requests, the payload is a [CustomCheckpointRequest]. The response is
  /// a nullable string.
  customCheckpointRequest,

  /// Request a checkpoint from the sync client.
  requestCheckpoint,

  invalidCredentialsCallback,
  credentialsCallback,

  /// Notifies clients that the sync status has changed - the payload consists
  /// of [SerializedSyncStatus].
  notifySyncStatus,

  /// Notifies clients of a diagnostics event from the core extension. The
  /// payload is a JSON string of the event.
  handleDiagnostics,

  /// Notifies clients about a log event emitted by the worker (typically only
  /// used when workers were compiled in debug mode).
  /// The payload is a [JSString].
  logEvent,

  /// Send an HTTP request.
  ///
  /// The request payload is a [HttpRequest], the response is a [HttpResponse].
  sendHttpRequest,

  /// Abort an in-flight HTTP request.
  ///
  /// The payload is an [AbortHttpResponse] object.
  abortHttpRequest,

  /// Requests a chunk of data from an HTTP response.
  ///
  /// The request payload is a [ReadStreamChunk], the response is a
  /// [JSArrayBuffer] (or `null` if the end of the response was reached).
  readResponseChunk,

  okResponse,
  errorResponse,
}

@anonymous
extension type SyncWorkerMessage._(JSObject _) implements JSObject {
  external factory SyncWorkerMessage({
    required String type,
    required JSAny payload,
  });

  external String get type;
  external JSAny get payload;
}

@anonymous
extension type StartSynchronization._(JSObject _) implements JSObject {
  external factory StartSynchronization({
    required String databaseName,
    required int crudThrottleTimeMs,
    required int requestId,
    required int retryDelayMs,
    required String schemaJson,
    required String lockName,
    String? syncParamsEncoded,
    UpdateSubscriptions? subscriptions,
    String? appMetadataEncoded,
    bool? customHttpClient,
    int? checkpointModeRequestsDelay,
    bool? diagnostics,
    required bool hasAuthenticator,
    required bool hasUploader,
  });

  external String get databaseName;
  external int get requestId;
  external int get crudThrottleTimeMs;
  external int? get retryDelayMs;
  external String get schemaJson;
  external String? get syncParamsEncoded;
  external UpdateSubscriptions? get subscriptions;
  external String? get appMetadataEncoded;
  external String get lockName;
  external bool? get customHttpClient;
  external int? checkpointModeRequestsDelay;
  external bool? diagnostics;
  external bool? get hasAuthenticator;
  external bool? get hasUploader;
}

@anonymous
extension type UpdateSubscriptions._raw(JSObject _inner) implements JSObject {
  external factory UpdateSubscriptions._({
    required int requestId,
    required JSArray content,
  });

  factory UpdateSubscriptions(int requestId, List<SubscribedStream> streams) {
    return UpdateSubscriptions._(
      requestId: requestId,
      content: streams
          .map((e) => <JSString>[e.name.toJS, e.parameters.toJS].toJS)
          .toList()
          .toJS,
    );
  }

  external int get requestId;
  external JSArray get content;

  List<SubscribedStream> get toDart {
    return content.toDart.map((e) {
      final [name, parameters] = (e as JSArray<JSString>).toDart;

      return (name: name.toDart, parameters: parameters.toDart);
    }).toList();
  }
}

@anonymous
extension type WebEndpoint._(JSObject _) implements JSObject {
  external factory WebEndpoint({
    required String databaseName,
    required MessagePort databasePort,
    required String? lockName,
  });

  external String get databaseName;
  external String? get lockName;
  external MessagePort get databasePort;
}

@anonymous
extension type OkResponse._(JSObject _) implements JSObject {
  external factory OkResponse({
    required int requestId,
    required JSAny? payload,
  });

  external int get requestId;
  external JSAny? get payload;
}

@anonymous
extension type ErrorResponse._(JSObject _) implements JSObject {
  external factory ErrorResponse({
    required int requestId,
    required int? recognizedType,
    required JSString errorMessage,
  });

  external int get requestId;
  external int? get recognizedType;
  external JSString get errorMessage;

  static const recognizedTypeNone = 0;
  static const recognizedTypeRequestAbortedException = 1;
}

@anonymous
extension type SerializedCredentials._(JSObject _) implements JSObject {
  external factory SerializedCredentials({
    required JSString endpoint,
    required JSString token,
    required JSString? userId,
    required JSNumber? expiresAt,
  });

  factory SerializedCredentials.from(PowerSyncCredentials credentials) {
    return SerializedCredentials(
      endpoint: credentials.endpoint.toJS,
      token: credentials.token.toJS,
      userId: credentials.userId?.toJS,
      expiresAt: credentials.expiresAt?.microsecondsSinceEpoch.toJS,
    );
  }

  external JSString get endpoint;
  external JSString get token;
  external JSString? get userId;
  external JSNumber? get expiresAt;

  PowerSyncCredentials asCredentials() {
    return PowerSyncCredentials(
      endpoint: endpoint.toDart,
      token: token.toDart,
      userId: userId?.toDart,
      expiresAt: expiresAt.isUndefinedOrNull
          ? null
          : DateTime.fromMicrosecondsSinceEpoch(expiresAt!.toDartInt),
    );
  }
}

@anonymous
extension type SerializedSyncStatusUpdate._(JSObject _) implements JSObject {
  external factory SerializedSyncStatusUpdate({
    JSAny? core,
    JSBoolean? uploading,
    JSAny? downloadError,
    JSAny? uploadError,
  });

  external JSString? core;
  external JSBoolean? uploading;
  external JSAny? downloadError;
  external JSAny? uploadError;

  SyncStatusUpdate toDart() {
    CoreSyncStatus? core;
    if (this.core case final serialized?) {
      core = CoreSyncStatus.fromJson(
        json.decode(serialized.toDart) as Map<String, Object?>,
      );
    }

    return SyncStatusUpdate(
      core: core,
      uploading: uploading?.toDart,
      downloadError: _deserializeError(downloadError),
      uploadError: _deserializeError(uploadError),
    );
  }

  static JSAny? serializeError(Object? error) {
    return switch (error) {
      null => null,
      SyncStatusUpdate.resetSentinel => (-1).toJS,
      final error => error.toString().toJS,
    };
  }

  static Object? _deserializeError(JSAny? error) {
    if (error == null) return null;

    if (error.typeofEquals('number')) return SyncStatusUpdate.resetSentinel;
    return (error as JSString).toDart;
  }
}

@anonymous
extension type CustomCheckpointRequest._(JSObject _) implements JSObject {
  external factory CustomCheckpointRequest({
    required JSNumber req,
    required String clientId,
    required String requestId,
  });

  external JSNumber req;
  external String get clientId;
  external String get requestId;
}

final class WorkerCommunicationChannel {
  final Map<int, Completer<JSAny?>> _pendingRequests = {};
  final Completer<void> _closed = Completer();
  int _nextRequestId = 0;
  bool _hasError = false;
  bool _hasReceivedRemoteLockName = false;
  StreamSubscription<MessageEvent>? _incomingMessages;
  StreamSubscription<Event>? _incomingErrors;

  /// The name of a navigator lock held by this channel, it's sent to the remote
  /// when requested so that it can detect when this channel is closed.
  @visibleForTesting
  late final Future<String> lockName = _acquireLock();

  final MessagePort port;
  final FutureOr<(JSAny?, JSArray?)> Function(SyncWorkerMessageType, JSAny)
  requestHandler;
  final StreamController<(SyncWorkerMessageType, JSAny)> _events =
      StreamController();
  final Logger _logger;
  final RemoteHttpServer? _httpServer;

  Stream<(SyncWorkerMessageType, JSAny)> get events => _events.stream;

  Future<void> get closed => _closed.future;

  WorkerCommunicationChannel({
    required this.port,
    required this.requestHandler,
    Stream<Event>? errors,
    Logger? logger,
    Client? exposedHttpClient,
  }) : _logger = logger ?? autoLogger,
       _httpServer = exposedHttpClient == null
           ? null
           : RemoteHttpServer(exposedHttpClient) {
    port.start();
    _incomingErrors = errors?.listen((event) {
      _hasError = true;

      _pendingRequests.forEach((_, value) {
        value.completeError('Worker error: $event');
      });
      _pendingRequests.clear();
    });

    _incomingMessages = EventStreamProviders.messageEvent
        .forTarget(port)
        .listen((event) async {
          final message = event.data as SyncWorkerMessage;
          final type = SyncWorkerMessageType.values.byName(message.type);
          _logger.fine('[in] $type');

          int requestId;

          switch (type) {
            case SyncWorkerMessageType.ping:
              requestId = (message.payload as JSNumber).toDartInt;
              return _respond(requestId, () async => (null, null));
            case SyncWorkerMessageType.startSynchronization:
              requestId = (message.payload as StartSynchronization).requestId;
            case SyncWorkerMessageType.updateSubscriptions:
              requestId = (message.payload as UpdateSubscriptions).requestId;
            case SyncWorkerMessageType.requestEndpoint:
            case SyncWorkerMessageType.abortSynchronization:
            case SyncWorkerMessageType.credentialsCallback:
            case SyncWorkerMessageType.invalidCredentialsCallback:
            case SyncWorkerMessageType.uploadCrud:
            case SyncWorkerMessageType.requestCheckpoint:
              requestId = (message.payload as JSNumber).toDartInt;
            case SyncWorkerMessageType.customCheckpointRequest:
              requestId =
                  (message.payload as CustomCheckpointRequest).req.toDartInt;
            case SyncWorkerMessageType.sendHttpRequest:
              final request = message.payload as HttpRequest;
              return _respond(
                request.requestId,
                () async => (await _httpServer!.handle(request), null),
              );
            case SyncWorkerMessageType.abortHttpRequest:
              final payload = message.payload as AbortHttpResponse;
              _httpServer!.abort(payload.transactionId, payload.cancelStream);
              return;
            case SyncWorkerMessageType.readResponseChunk:
              final request = message.payload as ReadStreamChunk;
              return _respond(request.requestId, () async {
                return switch (await _httpServer!.readResponse(
                  request.transactionId,
                )) {
                  null => (null, null),
                  final buffer => (buffer, <JSAny?>[buffer].toJS),
                };
              });
            case SyncWorkerMessageType.okResponse:
              final payload = message.payload as OkResponse;
              _pendingRequests
                  .remove(payload.requestId)!
                  .complete(payload.payload);
              return;
            case SyncWorkerMessageType.errorResponse:
              final payload = message.payload as ErrorResponse;
              final error = switch (payload.recognizedType ??
                  ErrorResponse.recognizedTypeNone) {
                ErrorResponse.recognizedTypeRequestAbortedException =>
                  RequestAbortedException(),
                _ => payload.errorMessage.toDart,
              };

              _pendingRequests.remove(payload.requestId)!.completeError(error);
              return;
            case SyncWorkerMessageType.notifySyncStatus:
            case SyncWorkerMessageType.handleDiagnostics:
              _events.add((type, message.payload));
              return;
            case SyncWorkerMessageType.logEvent:
              final msg = (message.payload as JSString).toDart;
              _logger.info('[Sync Worker]: $msg');
              return;
          }

          await _respond(
            requestId,
            () => requestHandler(type, message.payload),
          );
        });
  }

  Future<void> _respond(
    int requestId,
    FutureOr<(JSAny?, JSArray?)> Function() generateResponse,
  ) async {
    try {
      final (response, transfer) = await generateResponse();
      final responseMessage = SyncWorkerMessage(
        type: SyncWorkerMessageType.okResponse.name,
        payload: OkResponse(requestId: requestId, payload: response),
      );

      if (transfer != null) {
        port.postMessage(responseMessage, transfer);
      } else {
        port.postMessage(responseMessage);
      }
    } catch (e) {
      port.postMessage(
        SyncWorkerMessage(
          type: SyncWorkerMessageType.errorResponse.name,
          payload: ErrorResponse(
            requestId: requestId,
            recognizedType: switch (e) {
              RequestAbortedException() =>
                ErrorResponse.recognizedTypeRequestAbortedException,
              _ => ErrorResponse.recognizedTypeNone,
            },
            errorMessage: e.toString().toJS,
          ),
        ),
      );
    }
  }

  (int, Future<JSAny?>) _newRequest() {
    if (_hasError || _closed.isCompleted) {
      throw StateError('Channel has error, cannot send new requests');
    }

    final id = _nextRequestId++;
    final completer = _pendingRequests[id] = Completer<JSAny?>.sync();
    return (id, completer.future);
  }

  Future<JSAny?> _numericRequest(SyncWorkerMessageType type) {
    final (id, future) = _newRequest();
    port.postMessage(SyncWorkerMessage(type: type.name, payload: id.toJS));
    return future;
  }

  void notify(SyncWorkerMessageType notificationType, JSAny payload) {
    port.postMessage(
      SyncWorkerMessage(type: notificationType.name, payload: payload),
    );
  }

  Future<void> ping() async {
    await _numericRequest(SyncWorkerMessageType.ping);
  }

  void observeRemoteLockName(String name) {
    if (!_hasReceivedRemoteLockName) {
      _hasReceivedRemoteLockName = true;
      // Once we're able to acquire this lock, we know the remote has closed.
      potentiallySharedMutex(name).lock(close);
    }
  }

  Future<void> startSynchronization(
    String databaseName,
    InternalConnector connector,
    ResolvedSyncOptions options,
    Schema schema,
    List<SubscribedStream> streams,
    bool customHttpClient,
  ) async {
    final (id, completion) = _newRequest();
    port.postMessage(
      SyncWorkerMessage(
        type: SyncWorkerMessageType.startSynchronization.name,
        payload: StartSynchronization(
          databaseName: databaseName,
          crudThrottleTimeMs: options.crudThrottleTime.inMilliseconds,
          retryDelayMs: options.retryDelay.inMilliseconds,
          requestId: id,
          schemaJson: jsonEncode(schema),
          syncParamsEncoded: switch (options.source.params) {
            null => null,
            final params => jsonEncode(params),
          },
          subscriptions: UpdateSubscriptions(-1, streams),
          appMetadataEncoded: switch (options.source.appMetadata) {
            null => null,
            final appMetadata => jsonEncode(appMetadata),
          },
          lockName: await lockName,
          customHttpClient: customHttpClient,
          checkpointModeRequestsDelay: switch (options.checkpointMode) {
            RequestsCheckpointMode(:final retryDelay) =>
              retryDelay.inMicroseconds,
            _ => null,
          },
          diagnostics: options.source.enableDiagnostics,
          hasAuthenticator: connector.authenticator != null,
          hasUploader: connector.uploader != null,
        ),
      ),
    );
    await completion;
  }

  Future<void> updateSubscriptions(List<SubscribedStream> streams) async {
    final (id, completion) = _newRequest();
    port.postMessage(
      SyncWorkerMessage(
        type: SyncWorkerMessageType.updateSubscriptions.name,
        payload: UpdateSubscriptions(id, streams),
      ),
    );

    await completion;
  }

  Future<void> abortSynchronization() async {
    await _numericRequest(SyncWorkerMessageType.abortSynchronization);
  }

  // Called by the sync worker to request a [WebEndpoint] for the database
  // managed by the client.
  Future<WebEndpoint> requestDatabase() async {
    return await _numericRequest(SyncWorkerMessageType.requestEndpoint)
        as WebEndpoint;
  }

  Future<PowerSyncCredentials?> credentialsCallback() async {
    final serialized =
        await _numericRequest(SyncWorkerMessageType.credentialsCallback)
            as SerializedCredentials?;
    return serialized?.asCredentials();
  }

  Future<PowerSyncCredentials?> invalidCredentialsCallback() async {
    final serialized =
        await _numericRequest(SyncWorkerMessageType.invalidCredentialsCallback)
            as SerializedCredentials?;
    return serialized?.asCredentials();
  }

  Future<void> uploadCrud() async {
    await _numericRequest(SyncWorkerMessageType.uploadCrud);
  }

  Future<String?> customCheckpointRequest(
    String clientId,
    String requestId,
  ) async {
    final (id, completion) = _newRequest();
    port.postMessage(
      SyncWorkerMessage(
        payload: CustomCheckpointRequest(
          req: id.toJS,
          clientId: clientId,
          requestId: requestId,
        ),
        type: SyncWorkerMessageType.customCheckpointRequest.name,
      ),
    );

    final response = await completion;
    return (response as JSString?)?.toDart;
  }

  Future<HttpResponse> sendHttpRequest(HttpRequest request) async {
    final (id, completion) = _newRequest();
    request.requestId = id;
    port.postMessage(
      SyncWorkerMessage(
        payload: request,
        type: SyncWorkerMessageType.sendHttpRequest.name,
      ),
      <JSAny?>[request.body].toJS,
    );
    return (await completion) as HttpResponse;
  }

  Future<JSArrayBuffer?> readHttpResponseChunk(int transactionId) async {
    final (id, completion) = _newRequest();
    port.postMessage(
      SyncWorkerMessage(
        type: SyncWorkerMessageType.readResponseChunk.name,
        payload: ReadStreamChunk(requestId: id, transactionId: transactionId),
      ),
    );

    return (await completion) as JSArrayBuffer?;
  }

  Future<JSBigInt> requestCheckpoint() async {
    final response = await _numericRequest(
      SyncWorkerMessageType.requestCheckpoint,
    );
    return response as JSBigInt;
  }

  Future<void> close() async {
    if (!_closed.isCompleted) {
      _incomingMessages?.cancel();
      _incomingErrors?.cancel();
      port.close();
      _httpServer?.forceClose();

      for (final pending in _pendingRequests.values) {
        pending.completeError(const ChannelClosedException());
      }

      _closed.complete();
    }
  }

  Future<String> _acquireLock() async {
    final name = _generateRandomLockName();
    final hasLock = Completer<void>.sync();
    potentiallySharedMutex(name).lock(() async {
      hasLock.complete();
      return _closed.future;
    });

    await hasLock.future;
    return name;
  }

  static String _generateRandomLockName() {
    final crypto = (globalContext['crypto'] as Crypto);
    return 'powersync-worker-keepalive-${crypto.randomUUID()}';
  }
}

final class RemoteAuthenticator implements InternalAuthenticator {
  final WorkerCommunicationChannel channel;

  RemoteAuthenticator(this.channel);

  @override
  bool get mightPostCheckpointRequests => true;

  @override
  Future<PowerSyncCredentials?> getCredentialsCached() =>
      channel.credentialsCallback();

  @override
  FutureOr<String?> postCheckpointRequest(
    String clientId,
    String checkpointRequestId,
  ) => channel.customCheckpointRequest(clientId, checkpointRequestId);

  @override
  Future<PowerSyncCredentials?> prefetchCredentials({
    bool invalidate = false,
  }) => channel.invalidCredentialsCallback();
}

final class RemoteUploader implements InternalMutationUploader {
  final WorkerCommunicationChannel channel;

  RemoteUploader(this.channel);

  @override
  Future<void> upload() => channel.uploadCrud();
}

final class ChannelClosedException implements Exception {
  const ChannelClosedException();

  @override
  String toString() {
    return 'Worker communication channel closed';
  }
}
