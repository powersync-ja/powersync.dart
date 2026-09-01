import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:bson/bson.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

final class MockSyncService {
  final bool useBson;

  // Use a queued stream to make tests easier.
  StreamController<Object /* String | Uint8List */> controller =
      StreamController();
  Completer<Request> _listener = Completer();

  var router = Router();
  FutureOr<Object?>? Function() writeCheckpoint = () {
    return {
      'data': {'write_checkpoint': '10'},
    };
  };

  var checkpointRequestsSupported = true;
  var lastCheckpointRequest = 0;
  var amountOfCheckpointRequests = 0;
  Future<void> Function()? beforeCheckpointRequestResponse;

  final _checkpointRequests = StreamController<void>.broadcast();

  MockSyncService({this.useBson = false}) {
    router
      ..post('/sync/stream', (Request request) async {
        if (useBson &&
            !request.headers['Accept']!.contains(
              'application/vnd.powersync.bson-stream',
            )) {
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

        return Response.ok(
          bytes,
          headers: {
            'Content-Type': useBson
                ? 'application/vnd.powersync.bson-stream'
                : 'application/x-ndjson',
            'Cache-Control': 'no-cache',
            'Connection': 'keep-alive',
          },
          context: {"shelf.io.buffer_output": false},
        );
      })
      ..get('/write-checkpoint2.json', (request) async {
        return Response.ok(
          json.encode(await writeCheckpoint()),
          headers: {'Content-Type': 'application/json'},
        );
      })
      ..post('/sync/checkpoint-request', (Request request) async {
        if (!checkpointRequestsSupported) {
          return Response.notFound('');
        }

        final body = jsonDecode(await request.readAsString());
        final requestId = lastCheckpointRequest = max(
          lastCheckpointRequest,
          int.parse(body['checkpoint_request_id'] as String),
        );

        await beforeCheckpointRequestResponse?.call();
        amountOfCheckpointRequests++;
        _checkpointRequests.add(null);

        return Response.ok(
          jsonEncode({
            'data': {'checkpoint_request_id': '$requestId'},
          }),
        );
      });
  }

  Future<Request> get waitForListener => _listener.future;

  Future<void> waitForCheckpointRequest(bool Function() check) async {
    if (check()) return;

    await for (final _ in _checkpointRequests.stream) {
      if (check()) return;
    }
  }

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
