import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:typed_data';

import 'package:web/web.dart' as web;
import 'package:path/path.dart' as p;
import 'local_storage.dart';

/// A [LocalStorage] implementation suitable for the web, storing files in the
/// [Origin private file system](https://developer.mozilla.org/en-US/docs/Web/API/File_System_API/Origin_private_file_system).
final class OpfsLocalStorage implements LocalStorage {
  final Future<web.FileSystemDirectoryHandle> Function() _root;
  Future<web.FileSystemDirectoryHandle>? _resolvedDirectory;

  OpfsLocalStorage._(this._root);

  /// Creates a [LocalStorage] implementation storing files in OPFS.
  ///
  /// The [rootDirectory] acts as a chroot within `navigator.getDirectory()`,
  /// and allows storing attachments in a subdirectory.
  /// Users are strongly encouraged to set it, as [clear] would otherwise delete
  /// all of OFPS.
  factory OpfsLocalStorage(String rootDirectory) {
    return OpfsLocalStorage._(() async {
      var root = await _navigator.storage.getDirectory().toDart;
      for (final segment in p.url.split(rootDirectory)) {
        root = await root.getDirectory(segment, create: true);
      }

      return root;
    });
  }

  Future<web.FileSystemDirectoryHandle> get root {
    return _resolvedDirectory ??= _root();
  }

  Future<(web.FileSystemDirectoryHandle, String)> _parentDirectoryAndName(
      String path,
      {bool create = false}) async {
    final segments = p.url.split(path);
    var dir = await root;
    for (var i = 0; i < segments.length - 1; i++) {
      dir = await dir.getDirectory(segments[i], create: create);
    }

    return (dir, segments.last);
  }

  Future<web.FileSystemFileHandle> _file(String path,
      {bool create = false}) async {
    final (parent, name) = await _parentDirectoryAndName(path, create: create);
    return await parent
        .getFileHandle(name, web.FileSystemGetFileOptions(create: create))
        .toDart;
  }

  @override
  Future<void> clear() async {
    final dir = await root;
    await for (final entry in dir.values().toDart) {
      await dir.remove(entry.name, recursive: true);
    }
  }

  @override
  Future<void> deleteFile(String filePath) async {
    try {
      final (parent, name) = await _parentDirectoryAndName(filePath);
      await parent.remove(name);
    } catch (e) {
      // Entry does not exist, skip.
      return;
    }
  }

  @override
  Future<bool> fileExists(String filePath) async {
    try {
      await _file(filePath);
      return true;
    } catch (e) {
      // Entry does not exist, skip.
      return false;
    }
  }

  @override
  Future<void> initialize() async {
    await root;
  }

  @override
  Stream<Uint8List> readFile(String filePath, {String? mediaType}) async* {
    final file = await _file(filePath);
    final completer = Completer<Uint8List>.sync();
    final reader = web.FileReader();
    reader
      ..onload = () {
        final data = (reader.result as JSArrayBuffer).toDart;
        completer.complete(data.asUint8List());
      }.toJS
      ..onerror = () {
        completer.completeError(reader.error!);
      }.toJS;

    reader.readAsArrayBuffer(await file.getFile().toDart);
    yield await completer.future;
  }

  @override
  Future<int> saveFile(String filePath, Stream<List<int>> data) async {
    final file = await _file(filePath, create: true);
    final writable = await file.createWritable().toDart;

    var bytesWritten = 0;
    await for (final chunk in data) {
      final asBuffer = switch (chunk) {
        final Uint8List blob => blob,
        _ => Uint8List.fromList(chunk),
      };

      await writable.write(asBuffer.toJS).toDart;
      bytesWritten += asBuffer.length;
    }

    await writable.close().toDart;
    return bytesWritten;
  }
}

@JS('Symbol.asyncIterator')
external JSSymbol get _asyncIterator;

@JS('navigator')
external web.Navigator get _navigator;

extension FileSystemHandleApi on web.FileSystemHandle {
  bool get isFile => kind == 'file';

  bool get isDirectory => kind == 'directory';
}

extension FileSystemDirectoryHandleApi on web.FileSystemDirectoryHandle {
  Future<web.FileSystemFileHandle> openFile(String name,
      {bool create = false}) {
    return getFileHandle(name, web.FileSystemGetFileOptions(create: create))
        .toDart;
  }

  Future<web.FileSystemDirectoryHandle> getDirectory(String name,
      {bool create = false}) {
    return getDirectoryHandle(
            name, web.FileSystemGetDirectoryOptions(create: create))
        .toDart;
  }

  Future<void> remove(String name, {bool recursive = false}) {
    return removeEntry(name, web.FileSystemRemoveOptions(recursive: recursive))
        .toDart;
  }

  external AsyncIterable<web.FileSystemHandle> values();
}

extension type IteratorResult<T extends JSAny?>(JSObject _)
    implements JSObject {
  external JSBoolean? get done;
  external T? get value;
}

extension type AsyncIterator<T extends JSAny?>(JSObject _) implements JSObject {
  external JSPromise<IteratorResult<T>> next();
}

extension type AsyncIterable<T extends JSAny?>(JSObject _) implements JSObject {
  Stream<T> get toDart async* {
    final iterator = (getProperty(_asyncIterator) as JSFunction)
        .callAsFunction(this) as AsyncIterator<T>;

    while (true) {
      final next = await iterator.next().toDart;
      if (next.done?.toDart == true) {
        break;
      }

      yield next.value as T;
    }
  }
}
