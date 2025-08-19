import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:meta/meta.dart';
import 'package:path/path.dart' as p;

import 'local_storage.dart';

/// Implements [LocalStorageAdapter] for device filesystem using Dart IO.
///
/// Handles file and directory operations for attachments.
@experimental
final class IOLocalStorage implements LocalStorageAdapter {
  final Directory _root;

  const IOLocalStorage(this._root);

  File _fileFor(String filePath) => File(p.join(_root.path, filePath));

  @override
  Future<int> saveFile(String filePath, List<int> data) async {
    final file = _fileFor(filePath);
    await file.parent.create(recursive: true);
    await file.writeAsBytes(data, flush: true);
    return data.length;
  }

  @override
  Stream<Uint8List> readFile(String filePath, {String? mediaType}) async* {
    final file = _fileFor(filePath);
    if (!await file.exists()) {
      throw FileSystemException('File does not exist', filePath);
    }
    final source = file.openRead();
    await for (final chunk in source) {
      yield chunk is Uint8List ? chunk : Uint8List.fromList(chunk);
    }
  }

  @override
  Future<void> deleteFile(String filePath) async {
    final file = _fileFor(filePath);
    if (await file.exists()) {
      await file.delete();
    }
  }

  @override
  Future<bool> fileExists(String filePath) async {
    return await _fileFor(filePath).exists();
  }

  /// Creates a directory and all necessary parent directories dynamically if they do not exist.
  @override
  Future<void> initialize() async {
    await _root.create(recursive: true);
  }

  @override
  Future<void> clear() async {
    if (await _root.exists()) {
      await _root.delete(recursive: true);
    }
    await _root.create(recursive: true);
  }
}
