/// @docImport 'package:powersync_core/attachments/io.dart';
library;

import 'dart:typed_data';

import 'package:meta/meta.dart';

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
abstract interface class LocalStorageAdapter {
  /// Saves binary data stream to storage at the specified file path
  ///
  /// [filePath] - Path where the file will be stored
  /// [data] - List of binary data to store
  /// Returns the total size of the written data in bytes
  Future<int> saveFile(String filePath, List<int> data);

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
