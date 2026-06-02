import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:typed_data';

import 'package:http/http.dart';
import 'package:web/web.dart' show Crypto;

import '../../platform_specific/web.dart';
import 'protocol.dart';

final class RemoteHttpServer {
  /// The http client to expose to a worker.
  final Client client;

  final Map<int, _HttpRequest> _pendingTransactions = {};

  RemoteHttpServer(this.client);

  Future<(HttpResponse, JSArray?)> handle(HttpRequest request) async {
    final state = _HttpRequest();
    _pendingTransactions[request.transactionId] = state;

    final lockName = await state.acquireLock();
    final inner = AbortableRequest(request.method, Uri.parse(request.uri),
        abortTrigger: state._abortController.future);
    inner.bodyBytes = request.body.toDart.asUint8List();
    request.decodedHeaders.forEach((k, v) => inner.headers[k] = v);

    final response = await client.send(inner);
    state.response = StreamIterator(response.stream);

    return (
      HttpResponse(
        lockName: lockName,
        statusCode: response.statusCode,
        headers: json.encode(response.headers),
      ),
      null
    );
  }

  Future<(JSArrayBuffer?, JSArray?)> readResponse(int transactionId) async {
    final state = _pendingTransactions[transactionId];
    final response = state?.response;
    if (state == null || response == null) {
      throw ArgumentError('Unknown HTTP transaction: $transactionId');
    }

    if (await response.moveNext()) {
      final asJsBuffer = _byteListToArrayBuffer(response.current);
      return (asJsBuffer, <JSAny?>[asJsBuffer].toJS);
    } else if (state._abortController.isCompleted) {
      throw RequestAbortedException();
    } else {
      // End of stream
      _pendingTransactions.remove(transactionId);
      state.close();

      return (null, null);
    }
  }

  void abort(int transactionId, bool cancelStream) {
    _pendingTransactions.remove(transactionId)?.abort(cancelStream);
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

  Future<String> acquireLock() async {
    final name = _generateRandomLockName();
    final hasLock = Completer<void>.sync();
    potentiallySharedMutex(name).lock(() async {
      hasLock.complete();
      return _abortController.future;
    });

    await hasLock.future;
    return name;
  }

  static String _generateRandomLockName() {
    final crypto = (globalContext['crypto'] as Crypto);
    return 'http-remote-${crypto.randomUUID()}';
  }
}
