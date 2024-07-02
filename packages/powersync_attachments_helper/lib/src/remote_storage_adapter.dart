import 'dart:io';
import 'dart:typed_data';

/// Abstract class used to implement the remote storage adapter
abstract class AbstractRemoteStorageAdapter {
  /// Upload file to remote storage
  Future<String?> uploadFile(String filePath, File file, {String mediaType});

  /// Download file from remote storage
  Future<Uint8List> downloadFile(String filePath);

  /// Delete file from remote storage
  Future<void> deleteFile(String filename);
}
