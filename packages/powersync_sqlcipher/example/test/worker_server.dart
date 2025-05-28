import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as io;
import 'package:shelf_static/shelf_static.dart';
import 'package:stream_channel/stream_channel.dart';

const _corsHeaders = {'Access-Control-Allow-Origin': '*'};

Middleware cors() {
  Response? handleOptionsRequest(Request request) {
    if (request.method == 'OPTIONS') {
      return Response.ok(null, headers: _corsHeaders);
    } else {
      // Returning null will run the regular request handler
      return null;
    }
  }

  Response addCorsHeaders(Response response) {
    return response.change(headers: _corsHeaders);
  }

  return createMiddleware(
    requestHandler: handleOptionsRequest,
    responseHandler: addCorsHeaders,
  );
}

Future<void> hybridMain(StreamChannel<Object?> channel) async {
  final sqliteOutputPath = p.join('web', 'sqlite3mc.wasm');

  if (!(await File(sqliteOutputPath).exists())) {
    throw AssertionError(
      'sqlite3mc.wasm file should be present in the ./web folder',
    );
  }

  final server = await HttpServer.bind('localhost', 0);

  final handler = const Pipeline()
      .addMiddleware(cors())
      .addHandler(createStaticHandler('web'));
  io.serveRequests(server, handler);

  channel.sink.add(server.port);
  await channel.stream.listen(null).asFuture<void>().then<void>((_) async {
    await server.close();
  });
}
