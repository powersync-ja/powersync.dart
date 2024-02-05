import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as io;
import 'package:shelf_static/shelf_static.dart';
import 'package:stream_channel/stream_channel.dart';
import 'package:test/test.dart';

import 'asset_server.dart';

Future<void> hybridMain(StreamChannel<Object?> channel) async {
  final directory = Directory('./assets');

  // Copy sqlite3.wasm file expected by the worker
  final sqliteOutputPath = p.join(directory.path, 'sqlite3.wasm');
  print(sqliteOutputPath);

  if (!(await File(sqliteOutputPath).exists())) {
    throw AssertionError(
        'sqlite3.wasm file should be present in the ./assets folder');
  }

  final driftWorkerPath = p.join(directory.path, 'drift_worker.js');

  if (!(await File(driftWorkerPath).exists())) {
    print('Compiling Drift worker');
    // And compile worker code
    final process = await Process.run(Platform.executable, [
      'compile',
      'js',
      '-o',
      driftWorkerPath,
      '-O0',
      'lib/src/web/worker/drift_worker.dart',
    ]);
    if (process.exitCode != 0) {
      fail('Could not compile worker');
    }
  }

  final server = await HttpServer.bind('localhost', 0);

  final handler = const Pipeline()
      .addMiddleware(cors())
      .addHandler(createStaticHandler(directory.path));
  io.serveRequests(server, handler);

  channel.sink.add(server.port);
  await channel.stream.listen(null).asFuture<void>().then<void>((_) async {
    print('closing server');
    await server.close();
  });
}
