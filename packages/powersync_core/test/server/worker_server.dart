import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as io;
import 'package:shelf_static/shelf_static.dart';
import 'package:stream_channel/stream_channel.dart';
import 'asset_server.dart';

Future<void> hybridMain(StreamChannel<Object?> channel) async {
  final assetsDirectory = p.normalize('assets');

  // Copy sqlite3.wasm file expected by the worker
  final sqliteOutputPath = p.join(assetsDirectory, 'sqlite3.wasm');

  if (!(await File(sqliteOutputPath).exists())) {
    throw AssertionError(
        'sqlite3.wasm file should be present in the powersync_core/assets folder');
  }

  final workerOutputPath = p.join(assetsDirectory, 'powersync_db.worker.js');

  if (!(await File(workerOutputPath).exists())) {
    throw AssertionError(
        'powersync_db.worker.js file should be present in the powersync_core/assets folder');
  }

  final server = await HttpServer.bind('localhost', 0);

  final handler = const Pipeline()
      .addMiddleware(cors())
      .addHandler(createStaticHandler(assetsDirectory));
  io.serveRequests(server, handler);

  channel.sink.add(server.port);
  await channel.stream.listen(null).asFuture<void>().then<void>((_) async {
    print('closing server');
    await server.close();
  });
}
