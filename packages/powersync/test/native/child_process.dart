import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:powersync/native.dart';

/// A child process for `file_mutex_test.dart`. Takes lock commands via stdin
/// and reports progress on stdout.
void main() async {
  print(json.encode('ready'));

  late Directory directory;

  final locks = <String, FileMutex>{};
  final releaseLocks = <int, Completer<void>>{};

  await for (final line
      in stdin
          .map(utf8.decode)
          .transform(const LineSplitter())
          .map(json.decode)) {
    switch (line) {
      case {'use_directory': final String dir}:
        directory = Directory(dir);
      case {'lock': final String name, 'id': final int id}:
        final lock = locks.putIfAbsent(name, () => FileMutex(directory, name));
        final release = Completer<void>();
        releaseLocks[id] = release;

        lock.lock(() async {
          print(json.encode({'locked': id}));
          await release.future;
        });
      case {'unlock': final int id}:
        releaseLocks.remove(id)?.complete();
    }
  }
}
