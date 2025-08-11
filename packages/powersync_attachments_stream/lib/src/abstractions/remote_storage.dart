import 'dart:async';
import '../attachment.dart';

/// Adapter for interfacing with remote attachment storage.
abstract class AbstractRemoteStorageAdapter {
  /// Uploads a file to remote storage.
  ///
  /// [fileData] is a stream of byte arrays representing the file data.
  /// [attachment] is the attachment record associated with the file.
  Future<void> uploadFile(
    Stream<List<int>> fileData,
    Attachment attachment,
  );

  /// Downloads a file from remote storage.
  ///
  /// [attachment] is the attachment record associated with the file.
  /// Returns a stream of byte arrays representing the file data.
  Future<Stream<List<int>>> downloadFile(Attachment attachment);

  /// Deletes a file from remote storage.
  ///
  /// [attachment] is the attachment record associated with the file.
  Future<void> deleteFile(Attachment attachment);
}
