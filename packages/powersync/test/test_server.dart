import 'dart:async';
import 'dart:convert' as convert;
import 'dart:io';

import 'package:http/http.dart' show ByteStream;
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_router/shelf_router.dart';

Future<HttpServer> createServer() async {
  var app = Router();

  app.post('/sync/stream', handleSyncStream);
  // Open on an arbitrary open port
  var server = await shelf_io.serve(app.call, 'localhost', 0);
  return server;
}

/// Convert Map -> ndjson ByteStream
ByteStream encodeNdjson(Stream<Object> jsonInput) {
  final stringInput = jsonInput.map((data) => '${convert.jsonEncode(data)}\n');
  final byteInput = stringInput.transform(convert.utf8.encoder);
  return ByteStream(byteInput);
}

Future<Response> handleSyncStream(Request request) async {
  stream() async* {
    var blob = "*" * 5000;
    for (var i = 0; i < 50; i++) {
      yield {"token_expires_in": 5, "blob": blob};
      await Future.delayed(Duration(microseconds: 1));
    }
  }

  return Response.ok(
    encodeNdjson(stream()),
    headers: {
      'Content-Type': 'application/x-ndjson',
    },
    context: {
      'shelf.io.buffer_output': false,
    },
  );
}
