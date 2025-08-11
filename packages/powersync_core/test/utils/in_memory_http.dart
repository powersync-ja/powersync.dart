import 'package:http/http.dart';
import 'package:http/testing.dart';
import 'package:shelf/shelf.dart' as shelf;

final Uri mockHttpUri = Uri.parse('https://testing.powersync.com/');

/// Returns a [Client] that can send HTTP requests to the returned
/// [shelf.Server].
///
/// The server can be used to serve shelf routes via [shelf.Server.mount].
(Client, shelf.Server) inMemoryServer() {
  final server = _MockServer();
  final client = MockClient.streaming(server.handleRequest);

  return (client, server);
}

final class _MockServer implements shelf.Server {
  shelf.Handler? _handler;

  @override
  void mount(shelf.Handler handler) {
    if (_handler != null) {
      throw StateError('already has a handler');
    }

    _handler = handler;
  }

  @override
  Future<void> close() async {}

  @override
  Uri get url => mockHttpUri;

  Future<StreamedResponse> handleRequest(
      BaseRequest request, ByteStream body) async {
    final cancellationFuture = switch (request) {
      Abortable(:final abortTrigger) => abortTrigger,
      _ => null,
    };

    if (_handler case final endpoint?) {
      final shelfRequest = shelf.Request(
        request.method,
        request.url,
        headers: request.headers,
        body: body,
      );

      final shelfResponse = await Future.any<shelf.Response>([
        Future.sync(() => endpoint(shelfRequest)),
        if (cancellationFuture != null)
          cancellationFuture.then((_) {
            throw RequestAbortedException();
          }),
      ]);

      return StreamedResponse(
        shelfResponse.read().injectCancellation(cancellationFuture),
        shelfResponse.statusCode,
        headers: shelfResponse.headers,
      );
    } else {
      throw StateError('Request before handler was set on mock server');
    }
  }
}

extension<T> on Stream<T> {
  Stream<T> injectCancellation(Future<void>? token) {
    if (token == null) {
      return this;
    }

    return Stream.multi(
      (listener) {
        final subscription = listen(
          listener.addSync,
          onError: listener.addErrorSync,
          onDone: listener.closeSync,
        );

        listener
          ..onPause = subscription.pause
          ..onResume = subscription.resume
          ..onCancel = subscription.cancel;

        token.whenComplete(() {
          if (!listener.isClosed) {
            listener
              ..addErrorSync(RequestAbortedException())
              ..closeSync();
            subscription.cancel();
          }
        });
      },
      isBroadcast: isBroadcast,
    );
  }
}
