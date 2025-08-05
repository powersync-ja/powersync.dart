import 'attachment_context.dart';

abstract class AttachmentService {
  Stream<void> watchActiveAttachments();
  Future<T> withContext<T>(Future<T> Function(AttachmentContext ctx) action);
}