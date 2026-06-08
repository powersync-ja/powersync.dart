import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:http/http.dart';

import 'protocol.dart';

/// A proxy exposing an HTTP [Client] through a message port protocol.
final class RemoteHttpServer {
  /// The http client to expose to a worker.
  final Client client;

  final Map<int, _HttpRequest> _pendingTransactions = {};

  RemoteHttpServer(this.client);

  /// Handles an http request, returning the serialized response.
  ///
  /// The response does not include a body, which must be read in chunks via
  /// [readResponse].
  Future<HttpResponse> handle(HttpRequest request) async {
    final state = _HttpRequest();
    _pendingTransactions[request.transactionId] = state;

    final inner = AbortableRequest(request.method, Uri.parse(request.uri),
        abortTrigger: state._abortController.future);
    inner.bodyBytes = request.body.toDart.asUint8List();
    request.decodedHeaders.forEach((k, v) => inner.headers[k] = v);

    final response = await client.send(inner);
    state.response = StreamIterator(response.stream);

    return HttpResponse(
      statusCode: response.statusCode,
      headers: json.encode(response.headers),
    );
  }

  /// Reads a chunk of an HTTP response stream.
  ///
  /// Returns the chunk as an array buffer, or null if the end of the stream has
  /// been reached.
  Future<JSArrayBuffer?> readResponse(int transactionId) async {
    final state = _pendingTransactions[transactionId];
    final response = state?.response;
    if (state == null || response == null) {
      throw ArgumentError('Unknown HTTP transaction: $transactionId');
    }

    try {
      if (await response.moveNext()) {
        return _byteListToArrayBuffer(response.current);
      } else if (state._abortController.isCompleted) {
        throw RequestAbortedException();
      } else {
        // End of stream
        _pendingTransactions.remove(transactionId);
        state.close();

        return null;
      }
    } on Object {
      state.close();
      rethrow;
    }
  }

  void abort(int transactionId, bool cancelStream) {
    _pendingTransactions.remove(transactionId)?.abort(cancelStream);
  }

  void forceClose() {
    for (final pending in _pendingTransactions.values) {
      pending.close();
    }
    _pendingTransactions.clear();

    client.close();
  }

  static JSArrayBuffer _byteListToArrayBuffer(List<int> bytes) {
    if (bytes is Uint8List) {
      final buffer = bytes.buffer;
      if (bytes.offsetInBytes == 0 && buffer.lengthInBytes == bytes.length) {
        // Not a sublist view, we can transfer the buffer at once.
        return buffer.toJS;
      }
    }

    return Uint8List.fromList(bytes).buffer.toJS;
  }
}

final class _HttpRequest {
  var _closed = false;

  final Completer<void> _abortController = Completer.sync();
  StreamIterator<List<int>>? response;

  void close() {
    if (!_closed) {
      _closed = true;

      response?.cancel();
      abort(false);
    }
  }

  void abort(bool abortStream) {
    if (!_abortController.isCompleted) {
      if (abortStream) {
        response?.cancel();
      }

      _abortController.complete();
    }
  }
}
