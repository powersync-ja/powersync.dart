import 'dart:typed_data';

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
  /// Returns true if the file exists, false otherwise
  Future<bool> fileExists(String filePath);

  /// Initializes the storage, performing any necessary setup.
  Future<void> initialize();

  /// Clears all data from the storage.
  Future<void> clear();
}
