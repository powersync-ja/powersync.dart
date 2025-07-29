import '../attachment.dart';

abstract class AttachmentContext {
  Future<void> deleteAttachment(String id, dynamic tx);
  Future<void> ignoreAttachment(String id);
  Future<Attachment?> getAttachment(String id);
  Future<Attachment> saveAttachment(Attachment attachment);
  Future<void> saveAttachments(List<Attachment> attachments);
  Future<List<String>> getAttachmentIds();
  Future<List<Attachment>> getAttachments();
  Future<List<Attachment>> getActiveAttachments();
  Future<void> clearQueue();
  Future<bool> deleteArchivedAttachments(Future<void> Function(List<Attachment>) callback);
  Future<Attachment> upsertAttachment(Attachment attachment, dynamic context);
}