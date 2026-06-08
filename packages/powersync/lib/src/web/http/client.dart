import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:http/http.dart';

import '../sync_worker_protocol.dart';
import 'protocol.dart';

/// An HTTP client implemented through `postMessage` calls on message ports.
///
/// The sync worker uses this when a connecting tab indicates that a custom
/// HTTP client (which we can't send through ports as an object) should be used.
final class RemoteHttpClient extends BaseClient {
  final WorkerCommunicationChannel _channel;

  int _nextTransactionId = 0;

  RemoteHttpClient(this._channel);

  @override
  Future<StreamedResponse> send(BaseRequest request) async {
    final body = await request.finalize().toBytes();
    final bodyBuffer = body.buffer;
    // This will always be the case with the toBytes() implementation. We
    // couldn't safely transfer the entire buffer if body was a sublist view.
    assert(body.offsetInBytes == 0 && body.length == bodyBuffer.lengthInBytes);
    final jsBuffer = bodyBuffer.toJS;

    final txId = _nextTransactionId++;

    // Send request with other port.
    final responseFuture = _channel.sendHttpRequest(
      HttpRequest(
        requestId: 0, // Set by sendHttpRequest
        transactionId: txId,
        uri: request.url.toString(),
        method: request.method,
        headers: json.encode(request.headers),
        body: jsBuffer,
      ),
    );

    if (request is Abortable) {
      request.abortTrigger?.whenComplete(() => sendAbort(txId, false));
    }

    final rawResponse = await responseFuture;

    return StreamedResponse(
      _ResponseStream(this, txId).stream,
      rawResponse.statusCode,
      request: request,
      headers: rawResponse.decodedHeaders,
    );
  }

  void sendAbort(int txId, bool abortStream) {
    _channel.port.postMessage(
      SyncWorkerMessage(
        type: SyncWorkerMessageType.abortHttpRequest.name,
        payload: AbortHttpResponse(
          cancelStream: abortStream,
          transactionId: txId,
        ),
      ),
    );
  }
}

final class _ResponseStream {
  final RemoteHttpClient client;
  final int txId;

  final streamController = StreamController<Uint8List>(sync: true);
  var isFetching = false;

  Stream<Uint8List> get stream => streamController.stream;

  _ResponseStream(this.client, this.txId) {
    streamController
      ..onListen = fetchIfHasListener
      ..onResume = fetchIfHasListener
      ..onCancel = () => client.sendAbort(txId, true);
  }

  void fetchChunk() async {
    assert(!isFetching);
    isFetching = true;

    try {
      final chunk = await client._channel.readHttpResponseChunk(txId);
      if (chunk != null) {
        streamController.add(chunk.toDart.asUint8List());
      } else {
        streamController.close();
      }
    } catch (e, s) {
      streamController.addError(e, s);
      streamController.close();
    } finally {
      isFetching = false;
      fetchIfHasListener();
    }
  }

  void fetchIfHasListener() {
    if (!isFetching &&
        streamController.hasListener &&
        !streamController.isClosed &&
        !streamController.isPaused) {
      fetchChunk();
    }
  }
}
