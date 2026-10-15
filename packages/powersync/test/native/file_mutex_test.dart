@TestOn('vm')
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';
import 'package:test_descriptor/test_descriptor.dart' as d;

void main() {
  Future<_ChildProcess> spawn() async {
    final process = await _ChildProcess.spawn(Directory(d.sandbox));
    addTearDown(process.quit);
    return process;
  }

  test('single process', () async {
    final process = await spawn();

    final first = await process.lock('a');
    var hasSecond = false;
    final second = process.lock('a').whenComplete(() {
      hasSecond = true;
    });

    await Future<void>.delayed(const Duration(milliseconds: 200));
    expect(hasSecond, isFalse);
    first.complete();
    await second;
  });

  test('can manage multiple locks', () async {
    final process = await spawn();
    addTearDown(process.quit);

    await process.lock('a');
    await process.lock('b');
  });

  test('multiple processes', () async {
    final (a, b) = await (spawn(), spawn()).wait;

    final first = await a.lock('a');
    var hasSecond = false;
    final second = b.lock('a').whenComplete(() {
      hasSecond = true;
    });

    await Future<void>.delayed(const Duration(milliseconds: 200));
    expect(hasSecond, isFalse);
    first.complete();
    await second;
  });

  test('returns lock on exit', () async {
    final (a, b) = await (spawn(), spawn()).wait;

    await a.lock('a');
    var hasSecond = false;
    final second = b.lock('a').whenComplete(() {
      hasSecond = true;
    });

    await Future<void>.delayed(const Duration(milliseconds: 200));
    expect(hasSecond, isFalse);

    await a.quit();
    await second;
  });
}

final class _ChildProcess {
  final Process process;

  final Completer<void> _ready = Completer();
  final Completer<void> _closed = Completer();
  final Map<int, Completer<void>> _outstandingRequests = {};

  var _lockRequestId = 0;

  _ChildProcess(this.process) {
    process.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .map(json.decode)
        .listen((line) {
          switch (line) {
            case 'ready':
              _ready.complete();
            case {'locked': final int id}:
              _outstandingRequests.remove(id)?.complete();
          }
        });

    process.exitCode.whenComplete(() {
      if (!_ready.isCompleted) {
        _ready.completeError(StateError('Process closed'));
      }
      for (final outstanding in _outstandingRequests.values) {
        outstanding.completeError(StateError('Process closed'));
      }

      _closed.complete();
    });
  }

  void _command(Object? msg) {
    process.stdin.writeln(msg);
  }

  void _useDirectory(String path) {
    _command(json.encode({'use_directory': path}));
  }

  Future<Completer<void>> lock(String name) async {
    final id = _lockRequestId++;
    final didAcquire = Completer<void>();
    _outstandingRequests[id] = didAcquire;
    _command(json.encode({'lock': name, 'id': id}));

    await didAcquire.future;

    final releaseLock = Completer<void>();
    releaseLock.future.whenComplete(() {
      _command(json.encode({'unlock': id}));
    });
    return releaseLock;
  }

  Future<void> quit() async {
    await process.stdin.flush();
    await process.stdin.close();
    await _closed.future;
  }

  static Future<_ChildProcess> spawn(Directory directory) async {
    final process = await Process.start(Platform.resolvedExecutable, [
      'test/native/child_process.dart',
    ]);
    process.stderr.transform(utf8.decoder).listen(stderr.write);

    final wrapped = _ChildProcess(process);
    await wrapped._ready.future;

    wrapped._useDirectory(directory.path);
    return wrapped;
  }
}
