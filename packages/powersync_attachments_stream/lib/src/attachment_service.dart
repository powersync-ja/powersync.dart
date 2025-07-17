import 'attachment_state.dart';
import 'attachment_context.dart';

abstract class AttachmentService {
  Future<void> init();
  Future<void> close();

  Stream<List<Attachment>> watchActiveAttachments();
  Future<List<Attachment>> getActiveAttachments({AttachmentState? state});
  Future<void> triggerSync();
  Future<List<Attachment>> getAttachments({int? limit, int? offset});
  Future<void> withContext(Future<void> Function(AttachmentContext ctx) action);
}