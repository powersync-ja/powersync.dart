/// @docImport 'package:powersync_core/attachments/io.dart';
library;

import 'dart:typed_data';

import 'package:meta/meta.dart';
import 'package:path/path.dart' as p;

/// An interface responsible for storing attachment data locally.
///
/// This interface is only responsible for storing attachment content,
/// essentially acting as a key-value store of virtual paths to blobs.
///
/// On native platforms, you can use the [IOLocalStorage] implemention. On the
/// web, no default implementation is available at the moment.
///
/// {@category attachments}
@experimental
abstract interface class LocalStorage {
  /// Returns an in-memory [LocalStorage] implementation, suitable for testing.
  factory LocalStorage.inMemory() = _InMemoryStorage;

  /// Saves binary data stream to storage at the specified file path
  ///
  /// [filePath] - Path where the file will be stored
  /// [data] - List of binary data to store
  /// Returns the total size of the written data in bytes
  Future<int> saveFile(String filePath, Stream<List<int>> data);

  /// Retrieves binary data stream from storage at the specified file path
  ///
  /// [filePath] - Path of the file to read
  /// [mediaType] - Optional MIME type of the data
  /// Returns a stream of binary data
  Stream<Uint8List> readFile(String filePath, {String? mediaType});

  /// Deletes a file at the specified path
  ///
  /// [filePath] - Path of the file to delete
  Future<void> deleteFile(String filePath);

  /// Checks if a file exists at the specified path
  ///
  /// [filePath] - Path to check
  ///
  /// Returns true if the file exists, false otherwise
  Future<bool> fileExists(String filePath);

  /// Initializes the storage, performing any necessary setup.
  Future<void> initialize();

  /// Clears all data from the storage.
  Future<void> clear();
}

final class _InMemoryStorage implements LocalStorage {
  final Map<String, Uint8List> content = {};

  String _keyForPath(String path) {
    return p.normalize(path);
  }

  @override
  Future<void> clear() async {
    content.clear();
  }

  @override
  Future<void> deleteFile(String filePath) async {
    content.remove(_keyForPath(filePath));
  }

  @override
  Future<bool> fileExists(String filePath) async {
    return content.containsKey(_keyForPath(filePath));
  }

  @override
  Future<void> initialize() async {}

  @override
  Stream<Uint8List> readFile(String filePath, {String? mediaType}) {
    return switch (content[_keyForPath(filePath)]) {
      null =>
        Stream.error('file at $filePath does not exist in in-memory storage'),
      final contents => Stream.value(contents),
    };
  }

  @override
  Future<int> saveFile(String filePath, Stream<List<int>> data) async {
    var length = 0;
    final builder = BytesBuilder(copy: false);
    await for (final chunk in data) {
      length += chunk.length;
      builder.add(chunk);
    }

    content[_keyForPath(filePath)] = builder.takeBytes();
    return length;
  }
}
