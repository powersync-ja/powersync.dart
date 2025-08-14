import 'attachment_context.dart';

/// Service for interacting with the local attachment records.
abstract class AbstractAttachmentService {
  /// Watcher for changes to attachments table.
  /// Once a change is detected it will initiate a sync of the attachments.
  Stream<void> watchActiveAttachments({Duration? throttle});

  /// Executes a callback with an exclusive lock on all attachment operations.
  /// This helps prevent race conditions between different updates.
  Future<R> withContext<R>(
      Future<R> Function(AbstractAttachmentContext context) action);
}
