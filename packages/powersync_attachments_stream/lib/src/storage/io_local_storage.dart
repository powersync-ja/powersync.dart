/// Local storage adapter for handling file operations on the device filesystem.
///
/// This file implements the [IOLocalStorage] class, which provides methods for
/// saving, reading, deleting, copying, and managing files and directories using
/// the Dart IO library. It is used as the local storage backend for attachments
/// in the PowerSync attachments system.
///
/// Features:
/// - Save files from streams (creates directories and all necessary parents dynamically if they do not exist)
/// - Read files as streams
/// - Delete files and their metadata
/// - Copy files and their metadata
/// - Create and remove directories (creates all necessary parents dynamically)
/// - Check file existence

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:path/path.dart' as p;
import '../abstractions/local_storage.dart';

/// Implements [LocalStorage] for device filesystem using Dart IO.
///
/// Handles file and directory operations for attachments.
class IOLocalStorage implements LocalStorage {
  final Directory baseDir;

  IOLocalStorage(this.baseDir);

  File _fileFor(String filePath) => File(p.join(baseDir.path, filePath));
  File _metaFileFor(String filePath) =>
      File(p.join(baseDir.path, '$filePath.meta.json'));

  /// Saves a file from a stream of [Uint8List] chunks.
  /// Creates the file's directory and all necessary parent directories dynamically if they do not exist.
  /// Returns the total number of bytes written.
  @override
  Future<int> saveFile(String filePath, Stream<Uint8List> data) async {
    final file = _fileFor(filePath);
    await file.parent.create(recursive: true);
    var totalSize = 0;
    final sink = file.openWrite();
    try {
      await for (final chunk in data) {
        sink.add(chunk);
        totalSize += chunk.length;
      }
      await sink.flush();
    } finally {
      await sink.close();
    }
    return totalSize;
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
  Future<void> makeDir(String path) async {
    await Directory(p.join(baseDir.path, path)).create(recursive: true);
  }

  /// Recursively removes a directory and all its contents.
  @override
  Future<void> rmDir(String path) async {
    final dir = Directory(p.join(baseDir.path, path));
    if (await dir.exists()) {
      await for (final entity in dir.list(recursive: false)) {
        if (entity is Directory) {
          await rmDir(p.relative(entity.path, from: baseDir.path));
        } else if (entity is File) {
          await entity.delete();
        }
      }
      await dir.delete();
    }
  }

  /// Copies a file and its metadata to a new location.
  @override
  Future<void> copyFile(String sourcePath, String targetPath) async {
    final sourceFile = _fileFor(sourcePath);
    final targetFile = _fileFor(targetPath);
    if (!await sourceFile.exists()) {
      throw FileSystemException('Source file does not exist', sourcePath);
    }
    await targetFile.parent.create(recursive: true);
    await sourceFile.copy(targetFile.path);
    final sourceMeta = _metaFileFor(sourcePath);
    final targetMeta = _metaFileFor(targetPath);
    if (await sourceMeta.exists()) {
      await sourceMeta.copy(targetMeta.path);
    }
  }
}
