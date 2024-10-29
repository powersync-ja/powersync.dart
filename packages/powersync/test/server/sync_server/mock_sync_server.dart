import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as io;
import 'package:shelf_router/shelf_router.dart';

class TestHttpServerHelper {
  final StreamController<String> _controller = StreamController<String>();
  late HttpServer _server;
  // late Timer _timer;

  Uri get uri => Uri.parse('http://localhost:${_server.port}');

  // Start the HTTP server
  Future<void> start() async {
    final router = Router()
      ..post('/sync/stream', (Request request) async {
        // Respond immediately with a stream
        return Response.ok(_controller.stream.transform(utf8.encoder),
            headers: {
              'Content-Type': 'text/event-stream',
              'Cache-Control': 'no-cache',
              'Connection': 'keep-alive',
              'Transfer-Encoding': 'identity', // Use chunked transfer encoding
            },
            context: {
              "shelf.io.buffer_output": false
            });
      });

    // Sending a newline gets the stream going and resolving on the client side
    _controller.add("\n");

    // // Add data. The mock stream does not seem to resolve without data
    // _timer = Timer.periodic(Duration(seconds: 1), (Timer timer) {
    //   // This code will execute every second
    //   _controller.add('{ "token_expires_in": 3600}\n');
    // });

    _server = await io.serve(router, 'localhost', 0);
    print('Test server running at ${_server.address}:${_server.port}');
  }

  // Programmatically add data to the stream
  void addEvent(String data) {
    _controller.add(data);
  }

  // Stop the HTTP server
  Future<void> stop() async {
    // _timer.cancel();
    await _controller.close();
    await _server.close();
  }
}
