import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:bson/bson.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

final class MockSyncService {
  final bool useBson;

  // Use a queued stream to make tests easier.
  StreamController<Object /* String | Uint8List */ > controller =
      StreamController();
  Completer<Request> _listener = Completer();

  final router = Router();
  Object? Function() writeCheckpoint = () {
    return {
      'data': {'write_checkpoint': '10'}
    };
  };

  MockSyncService({this.useBson = false}) {
    router
      ..post('/sync/stream', (Request request) async {
        if (useBson &&
            !request.headers['Accept']!
                .contains('application/vnd.powersync.bson-stream')) {
          throw "Want to serve bson, but client doesn't accept it";
        }

        _listener.complete(request);
        // Respond immediately with a stream
        final bytes = controller.stream.map((line) {
          return switch (line) {
            final String line => utf8.encode(line),
            final Uint8List line => line,
            _ => throw ArgumentError.value(line, 'line', 'Unexpected type'),
          };
        });

        return Response.ok(bytes, headers: {
          'Content-Type': useBson
              ? 'application/vnd.powersync.bson-stream'
              : 'application/x-ndjson',
          'Cache-Control': 'no-cache',
          'Connection': 'keep-alive',
        }, context: {
          "shelf.io.buffer_output": false
        });
      })
      ..get('/write-checkpoint2.json', (request) {
        return Response.ok(json.encode(writeCheckpoint()), headers: {
          'Content-Type': 'application/json',
        });
      });
  }

  Future<Request> get waitForListener => _listener.future;

  // Queue events which will be sent to connected clients.
  void addRawEvent(Object data) {
    controller.add(data);
  }

  void addLine(Object? message) {
    if (useBson) {
      // Going through a JSON roundtrip ensures that the message can be
      // serialized with the BSON package.
      final cleanedMessage = json.decode(json.encode(message));
      addRawEvent(BsonCodec.serialize(cleanedMessage).byteList);
    } else {
      addRawEvent('${json.encode(message)}\n');
    }
  }

  void addKeepAlive([int tokenExpiresIn = 3600]) {
    addLine({'token_expires_in': tokenExpiresIn});
  }

  void endCurrentListener() {
    controller.close();
    controller = StreamController();
    _listener = Completer();
  }

  // Clear events. We rely on a buffered controller here. Create a new controller
  // in order to clear the buffer.
  Future<void> clearEvents() async {
    await controller.close();
    _listener = Completer();
    controller = StreamController<String>();
  }

  Future<void> stop() async {
    if (controller.hasListener) {
      await controller.close();
    }
  }
}
