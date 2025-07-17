import 'attachment_service.dart';
import 'attachment_state.dart';
import 'attachment_context.dart';
import 'local_storage.dart';
import 'sync_error_handler.dart';
import 'utils/mutex.dart';
import 'dart:async';

class AttachmentQueueService implements AttachmentService {
  final LocalStorage localStorage;
  final SyncErrorHandler errorHandler;
  final AsyncMutex _mutex = AsyncMutex();

  final StreamController<List<Attachment>> _activeAttachmentsController = StreamController.broadcast();
  final List<Attachment> _attachments = [];

  AttachmentQueueService({
    required this.localStorage,
    required this.errorHandler,
  });

  @override
  Future<void> init() async {
    // Initialize resources, DB, etc.
  }

  @override
  Future<void> close() async {
    await _activeAttachmentsController.close();
    // Clean up resources
  }

  @override
  Stream<List<Attachment>> watchActiveAttachments() => _activeAttachmentsController.stream;

  @override
  Future<List<Attachment>> getActiveAttachments({AttachmentState? state}) async {
    return _attachments.where((a) =>
      a.state != AttachmentState.archived &&
      (state == null || a.state == state)
    ).toList();
  }

  @override
  Future<void> triggerSync() async {
    // Implement sync logic, update states, handle errors
  }

  @override
  Future<List<Attachment>> getAttachments({int? limit, int? offset}) async {
    var list = List<Attachment>.from(_attachments);
    if (offset != null) list = list.skip(offset).toList();
    if (limit != null) list = list.take(limit).toList();
    return list;
  }

  @override
  Future<void> withContext(Future<void> Function(AttachmentContext ctx) action) async {
    await _mutex.protect(() async {
      final ctx = AttachmentContext();
      await action(ctx);
    });
  }

  // Add methods for adding, updating, removing attachments, etc.
}