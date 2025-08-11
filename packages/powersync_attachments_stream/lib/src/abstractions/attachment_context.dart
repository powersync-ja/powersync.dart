import '../attachment.dart';

/// Context for performing Attachment operations.
///
/// This is typically provided through a locking/exclusivity method and allows
/// safe, transactional operations on the attachment queue.
abstract class AbstractAttachmentContext {
  /// Delete the attachment from the attachment queue.
  ///
  /// [id]: The ID of the attachment to delete.
  /// [tx]: The database context to use for the operation.
  Future<void> deleteAttachment(String id, dynamic context);

  /// Set the state of the attachment to ignore.
  Future<void> ignoreAttachment(String id);

  /// Get the attachment from the attachment queue using an ID.
  Future<Attachment?> getAttachment(String id);

  /// Save the attachment to the attachment queue.
  Future<Attachment> saveAttachment(Attachment attachment);

  /// Save the attachments to the attachment queue.
  Future<void> saveAttachments(List<Attachment> attachments);

  /// Get all the IDs of attachments in the attachment queue.
  Future<List<String>> getAttachmentIds();

  /// Get all Attachment records present in the database.
  Future<List<Attachment>> getAttachments();

  /// Gets all the active attachments which require an operation to be performed.
  Future<List<Attachment>> getActiveAttachments();

  /// Helper function to clear the attachment queue. Currently only used for testing purposes.
  Future<void> clearQueue();

  /// Delete attachments which have been archived.
  ///
  /// Returns true if all items have been deleted. Returns false if there might be more archived items remaining.
  Future<bool> deleteArchivedAttachments(Future<void> Function(List<Attachment>) callback);

  /// Upserts an attachment record given a database connection context.
  ///
  /// [attachment]: The attachment to upsert.
  /// [context]: The database transaction/context to use for the operation.
  /// Returns the upserted [Attachment].
  Future<Attachment> upsertAttachment(Attachment attachment, dynamic context);
}