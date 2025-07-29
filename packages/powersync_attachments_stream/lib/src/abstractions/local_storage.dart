import 'dart:typed_data';

abstract class LocalStorage {
  /// Saves binary data stream to storage at the specified file path
  ///
  /// [filePath] - Path where the file will be stored
  /// [data] - Stream of binary data to store
  /// Returns the total size of the written data in bytes
  Future<int> saveFile(String filePath, Stream<Uint8List> data);

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

  /// Creates a directory at the specified path
  ///
  /// [path] - Path of the directory to create
  Future<void> makeDir(String path);

  /// Recursively removes a directory and its contents
  ///
  /// [path] - Path of the directory to remove
  Future<void> rmDir(String path);

  /// Copies a file from source to target path
  ///
  /// [sourcePath] - Path of the source file
  /// [targetPath] - Path where the file will be copied
  Future<void> copyFile(String sourcePath, String targetPath);
}
