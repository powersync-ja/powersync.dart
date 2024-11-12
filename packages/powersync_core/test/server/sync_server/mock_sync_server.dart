import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as io;
import 'package:shelf_router/shelf_router.dart';

// A basic Mock PowerSync service server which queues commands
// which clients can receive via connecting to the `/sync/stream` route.
// This assumes only one client will ever be connected at a time.
class TestHttpServerHelper {
  // Use a queued stream to make tests easier.
  StreamController<String> _controller = StreamController<String>();
  late HttpServer _server;
  Uri get uri => Uri.parse('http://localhost:${_server.port}');

  Future<void> start() async {
    final router = Router()
      ..post('/sync/stream', (Request request) async {
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
      });

    _server = await io.serve(router.call, 'localhost', 0);
    print('Test server running at ${_server.address}:${_server.port}');
  }

  // Queue events which will be sent to connected clients.
  void addEvent(String data) {
    _controller.add(data);
  }

  // Clear events. We rely on a buffered controller here. Create a new controller
  // in order to clear the buffer.
  Future<void> clearEvents() async {
    await _controller.close();
    _controller = StreamController<String>();
  }

  Future<void> stop() async {
    await _controller.close();
    await _server.close();
  }
}
