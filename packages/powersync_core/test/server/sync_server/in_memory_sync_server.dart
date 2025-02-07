import 'dart:async';
import 'dart:convert';

import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

final class MockSyncService {
  // Use a queued stream to make tests easier.
  StreamController<String> _controller = StreamController<String>();
  Completer<void> _listener = Completer();

  final router = Router();

  MockSyncService() {
    router
      ..post('/sync/stream', (Request request) async {
        _listener.complete();
        // Respond immediately with a stream
        return Response.ok(_controller.stream.transform(utf8.encoder),
            headers: {
              'Content-Type': 'application/x-ndjson',
              'Cache-Control': 'no-cache',
              'Connection': 'keep-alive',
            },
            context: {
              "shelf.io.buffer_output": false
            });
      })
      ..get('/write-checkpoint2.json', (request) {
        return Response.ok('{"data": {"write_checkpoint": "10"}}', headers: {
          'Content-Type': 'application/json',
        });
      });
  }

  Future<void> get waitForListener => _listener.future;

  // Queue events which will be sent to connected clients.
  void addRawEvent(String data) {
    _controller.add(data);
  }

  void addLine(Object? message) {
    addRawEvent('${json.encode(message)}\n');
  }

  void addKeepAlive([int tokenExpiresIn = 3600]) {
    addLine({'token_expires_in': tokenExpiresIn});
  }

  // Clear events. We rely on a buffered controller here. Create a new controller
  // in order to clear the buffer.
  Future<void> clearEvents() async {
    await _controller.close();
    _listener = Completer();
    _controller = StreamController<String>();
  }

  Future<void> stop() async {
    if (_controller.hasListener) {
      await _controller.close();
    }
  }
}
