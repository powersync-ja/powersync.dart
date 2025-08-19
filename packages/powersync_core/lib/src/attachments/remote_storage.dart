import 'dart:async';
import 'dart:typed_data';

import 'package:meta/meta.dart';

import 'attachment.dart';

/// An interface responsible for uploading and downloading attachments from a
/// remote source, like e.g. S3 or Firebase cloud storage.
///
/// {@category attachments}
@experimental
abstract interface class RemoteAttachmentStorage {
  /// Uploads a file to remote storage.
  ///
  /// [fileData] is a stream of byte arrays representing the file data.
  /// [attachment] is the attachment record associated with the file.
  Future<void> uploadFile(
    Stream<Uint8List> fileData,
    Attachment attachment,
  );

  /// Downloads a file from remote storage.
  ///
  /// [attachment] is the attachment record associated with the file.
  ///
  /// Returns a stream of byte arrays representing the file data.
  Future<Stream<List<int>>> downloadFile(Attachment attachment);

  /// Deletes a file from remote storage.
  ///
  /// [attachment] is the attachment record associated with the file.
  Future<void> deleteFile(Attachment attachment);
}
