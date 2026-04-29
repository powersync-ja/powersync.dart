@TestOn('vm')
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:powersync/src/version.dart';
import 'package:test/test.dart';
import 'package:vm_service/vm_service.dart';
import 'package:vm_service/vm_service_io.dart';

void main() {
  late Process child;
  late VmService vm;
  late String isolateId;
  late Directory tmpDir;

  setUpAll(() async {
    tmpDir = await Directory.systemTemp.createTemp('ps-dart-extension-test');

    // Get a random unused port.
    final socket = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final port = socket.port;
    await socket.close();

    String sdk = p.dirname(p.dirname(Platform.resolvedExecutable));
    child = await Process.start(p.join(sdk, 'bin', 'dart'), [
      // Don't use dart run here to avoid https://github.com/dart-lang/native/issues/2921.
      // Build hooks would have run for the parent process anyway.
      //'run',
      '--enable-vm-service=$port',
      '--disable-service-auth-codes',
      '--enable-asserts',
      'test/devtools/app.dart',
      p.join(tmpDir.path, 'test.db'),
    ]);

    final vmServiceListening = Completer<void>();
    final databaseOpened = Completer<void>();

    child.stdout.map(utf8.decode).transform(const LineSplitter()).listen((
      line,
    ) {
      print('[child]: $line');

      if (line.startsWith('The Dart VM service is listening')) {
        vmServiceListening.complete();
      } else if (line.contains('database is running')) {
        databaseOpened.complete();
      }
    });

    await vmServiceListening.future;

    vm = await vmServiceConnectUri('ws://localhost:$port/ws');
    await databaseOpened.future;

    final state = await vm.getVM();
    isolateId = state.isolates!.firstWhere((i) => i.name == 'main').id!;
  });

  tearDownAll(() async {
    child.kill();
    await child.exitCode;
    await tmpDir.delete(recursive: true);
  });

  test('can get version', () async {
    final response = await vm.callServiceExtension('ext.powersync.version',
        isolateId: isolateId);

    expect(response.json, {'version': libraryVersion});
  });

  test('can run queries', () async {
    final response = await vm.callServiceExtension(
      'ext.powersync.database',
      args: {
        'command': 'select',
        'db': '0',
        'sql': 'SELECT ?',
        'params': '[123]',
      },
      isolateId: isolateId,
    );
    expect(response.json, {
      'ok': {
        'columnNames': ['?'],
        'rows': [
          [123]
        ]
      }
    });
  });

  test('can get schema', () async {
    final response = await vm.callServiceExtension(
      'ext.powersync.database',
      args: {'command': 'schema', 'db': '0'},
      isolateId: isolateId,
    );
    expect(response.json, {
      'ok': {
        'raw_tables': <Object?>[],
        'tables': [containsPair('name', 'users')]
      }
    });
  });

  test('can get sync status', () async {
    final response = await vm.callServiceExtension(
      'ext.powersync.database',
      args: {'command': 'status-listen', 'db': '0'},
      isolateId: isolateId,
    );

    expect(response.json,
        {'ok': containsPair('current', containsPair('connected', false))});
  });
}
