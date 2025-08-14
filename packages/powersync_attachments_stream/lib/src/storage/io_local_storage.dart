import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;

import '../abstractions/local_storage.dart';

/// Implements [LocalStorageAdapter] for device filesystem using Dart IO.
///
/// Handles file and directory operations for attachments.
class IOLocalStorage implements LocalStorageAdapter {
  final String attachmentsDirectory;
  late final Directory baseDir;

  IOLocalStorage(this.attachmentsDirectory) {
    baseDir = Directory(attachmentsDirectory);
  }

  File _fileFor(String filePath) => File(p.join(baseDir.path, filePath));
  File _metaFileFor(String filePath) =>
      File(p.join(baseDir.path, '$filePath.meta.json'));

  /// Saves a file from a stream of [Uint8List] chunks.
  /// Creates the file's directory and all necessary parent directories dynamically if they do not exist.
  /// Returns the total number of bytes written.
  @override
  Future<int> saveFile(String filePath, List<int> data) async {
    final file = _fileFor(filePath);
    await file.parent.create(recursive: true);
    await file.writeAsBytes(data, flush: true);
    return data.length;
  }

  /// Reads a file as a stream of [Uint8List] chunks.
  /// Throws if the file does not exist.
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

  /// Deletes a file and its metadata file.
  @override
  Future<void> deleteFile(String filePath) async {
    final file = _fileFor(filePath);
    if (await file.exists()) {
      await file.delete();
    }
    final metaFile = _metaFileFor(filePath);
    if (await metaFile.exists()) {
      await metaFile.delete();
    }
  }

  /// Checks if a file exists.
  @override
  Future<bool> fileExists(String filePath) async {
    return await _fileFor(filePath).exists();
  }

  /// Creates a directory and all necessary parent directories dynamically if they do not exist.
  @override
  Future<void> initialize() async {
    await baseDir.create(recursive: true);
  }

  @override
  Future<void> clear() async {
    if (await baseDir.exists()) {
      await baseDir.delete(recursive: true);
    }
    await baseDir.create(recursive: true);
  }
}
