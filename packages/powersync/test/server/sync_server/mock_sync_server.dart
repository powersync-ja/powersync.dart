import 'dart:async';
import 'dart:io';

import 'package:shelf/shelf_io.dart' as io;

import 'in_memory_sync_server.dart';

// A basic Mock PowerSync service server which queues commands
// which clients can receive via connecting to the `/sync/stream` route.
// This assumes only one client will ever be connected at a time.
class TestHttpServerHelper {
  final MockSyncService service = MockSyncService();
  late HttpServer _server;

  Uri get uri => Uri.parse('http://localhost:${_server.port}');

  Future<void> start() async {
    _server = await io.serve(service.router.call, 'localhost', 0);
    print('Test server running at ${_server.address}:${_server.port}');
  }

  // Queue events which will be sent to connected clients.
  void addEvent(String data) {
    service.addRawEvent(data);
  }

  // Clear events. We rely on a buffered controller here. Create a new controller
  // in order to clear the buffer.
  Future<void> clearEvents() async {
    await service.clearEvents();
  }

  Future<void> stop() async {
    await service.stop();
    await _server.close();
  }
}
