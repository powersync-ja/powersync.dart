import 'package:meta/meta.dart';

import 'attachment.dart';

/// Interface for handling errors during attachment operations.
/// Implementations determine whether failed operations should be retried.
/// Attachment records are archived if an operation fails and should not be retried.
@experimental
abstract interface class AttachmentErrorHandler {
  /// Determines whether the provided attachment download operation should be retried.
  ///
  /// [attachment] The attachment involved in the failed download operation.
  /// [exception] The exception that caused the download failure.
  /// Returns `true` if the download operation should be retried, `false` otherwise.
  Future<bool> onDownloadError(
    Attachment attachment,
    Object exception,
  );

  /// Determines whether the provided attachment upload operation should be retried.
  ///
  /// [attachment] The attachment involved in the failed upload operation.
  /// [exception] The exception that caused the upload failure.
  /// Returns `true` if the upload operation should be retried, `false` otherwise.
  Future<bool> onUploadError(
    Attachment attachment,
    Object exception,
  );

  /// Determines whether the provided attachment delete operation should be retried.
  ///
  /// [attachment] The attachment involved in the failed delete operation.
  /// [exception] The exception that caused the delete failure.
  /// Returns `true` if the delete operation should be retried, `false` otherwise.
  Future<bool> onDeleteError(
    Attachment attachment,
    Object exception,
  );
}
