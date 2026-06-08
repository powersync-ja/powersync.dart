import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';

extension type HttpMessage._(JSObject _) implements JSObject {
  /// JSON-encoded request or response headers.
  @JS('h')
  external String headers;

  Map<String, String> get decodedHeaders {
    final decoded = json.decode(headers) as Map<String, Object?>;
    return decoded.cast();
  }
}

/// A serialized HTTP request.
extension type HttpRequest._(JSObject _) implements HttpMessage {
  external factory HttpRequest({
    @JS('r') required int requestId,
    @JS('i') required int transactionId,
    @JS('u') required String uri,
    @JS('m') required String method,
    @JS('h') required String headers,
    @JS('b') required JSArrayBuffer body,
  });

  @JS('r')
  external int requestId;

  /// A client-generated id for the HTTP transaction.
  ///
  /// This can be used to identify the request in subsequent commands to read
  /// or abort the response.
  @JS('i')
  external int transactionId;

  @JS('u')
  external String uri;

  @JS('m')
  external String method;

  /// The full request body (we don't support streaming request bodies, these
  /// aren't used by the SDK).
  @JS('b')
  external JSArrayBuffer body;
}

/// A serialized HTTP response
extension type HttpResponse._(JSObject _) implements HttpMessage {
  external factory HttpResponse({
    @JS('s') required int statusCode,
    @JS('h') required String headers,
  });

  @JS('s')
  external int statusCode;
}

/// A message sent to cancel an in-flight HTTP request.
extension type AbortHttpResponse._(JSObject _) implements JSObject {
  external factory AbortHttpResponse({
    @JS('r') required bool cancelStream,
    @JS('i') required int transactionId,
  });

  /// Whether the abort is from a [StreamSubscription.cancel] call (as opposed
  /// to an abort trigger on an abortable request).
  @JS('r')
  external bool cancelStream;

  /// The same as [HttpRequest.transactionId].
  @JS('i')
  external int transactionId;
}

/// A request to read a chunk of HTTP response data.
extension type ReadStreamChunk._(JSObject _) implements JSObject {
  external factory ReadStreamChunk({
    @JS('r') required int requestId,
    @JS('i') required int transactionId,
  });

  @JS('r')
  external int requestId;

  /// The same as [HttpRequest.transactionId].
  @JS('i')
  external int transactionId;
}
