import 'package:meta/meta.dart';

import 'attachment.dart';

/// The signature of a function handling an exception when uploading,
/// downloading or deleting an exception.
///
/// It returns `true` if the operation should be retried.
///
/// {@category attachments}
typedef AttachmentExceptionHandler = Future<bool> Function(
  Attachment attachment,
  Object exception,
  StackTrace stackTrace,
);

/// Interface for handling errors during attachment operations.
/// Implementations determine whether failed operations should be retried.
/// Attachment records are archived if an operation fails and should not be retried.
///
/// {@category attachments}
@experimental
abstract interface class AttachmentErrorHandler {
  /// Creates an implementation of an error handler by delegating to the
  /// individual functions for delete, download and upload errors.
  const factory AttachmentErrorHandler({
    required AttachmentExceptionHandler onDeleteError,
    required AttachmentExceptionHandler onDownloadError,
    required AttachmentExceptionHandler onUploadError,
  }) = _FunctionBasedErrorHandler;

  /// Determines whether the provided attachment download operation should be retried.
  ///
  /// [attachment] The attachment involved in the failed download operation.
  /// [exception] The exception that caused the download failure.
  /// [stackTrace] The [StackTrace] when the exception was caught.
  ///
  /// Returns `true` if the download operation should be retried, `false` otherwise.
  Future<bool> onDownloadError(
    Attachment attachment,
    Object exception,
    StackTrace stackTrace,
  );

  /// Determines whether the provided attachment upload operation should be retried.
  ///
  /// [attachment] The attachment involved in the failed upload operation.
  /// [exception] The exception that caused the upload failure.
  /// [stackTrace] The [StackTrace] when the exception was caught.
  ///
  /// Returns `true` if the upload operation should be retried, `false` otherwise.
  Future<bool> onUploadError(
    Attachment attachment,
    Object exception,
    StackTrace stackTrace,
  );

  /// Determines whether the provided attachment delete operation should be retried.
  ///
  /// [attachment] The attachment involved in the failed delete operation.
  /// [exception] The exception that caused the delete failure.
  /// [stackTrace] The [StackTrace] when the exception was caught.
  ///
  /// Returns `true` if the delete operation should be retried, `false` otherwise.
  Future<bool> onDeleteError(
    Attachment attachment,
    Object exception,
    StackTrace stackTrace,
  );
}

final class _FunctionBasedErrorHandler implements AttachmentErrorHandler {
  final AttachmentExceptionHandler _onDeleteError;
  final AttachmentExceptionHandler _onDownloadError;
  final AttachmentExceptionHandler _onUploadError;

  const _FunctionBasedErrorHandler(
      {required AttachmentExceptionHandler onDeleteError,
      required AttachmentExceptionHandler onDownloadError,
      required AttachmentExceptionHandler onUploadError})
      : _onDeleteError = onDeleteError,
        _onDownloadError = onDownloadError,
        _onUploadError = onUploadError;

  @override
  Future<bool> onDeleteError(
      Attachment attachment, Object exception, StackTrace stackTrace) {
    return _onDeleteError(attachment, exception, stackTrace);
  }

  @override
  Future<bool> onDownloadError(
      Attachment attachment, Object exception, StackTrace stackTrace) {
    return _onDownloadError(attachment, exception, stackTrace);
  }

  @override
  Future<bool> onUploadError(
      Attachment attachment, Object exception, StackTrace stackTrace) {
    return _onUploadError(attachment, exception, stackTrace);
  }
}
