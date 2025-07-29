import 'dart:async';
import 'package:logging/logging.dart';
import 'package:powersync_core/powersync_core.dart';

import '../abstractions/attachment_service.dart';
import '../abstractions/attachment_context.dart';
import '../attachment.dart';
import 'attachment_context.dart';

class AttachmentServiceImpl implements AttachmentService {
  final PowerSyncDatabase db;
  final Logger log;
  final int maxArchivedCount;
  final String attachmentsQueueTableName;
  Future<void> _mutex = Future.value();

  late final AttachmentContext _context;

  AttachmentServiceImpl({
    required this.db,
    required this.log,
    required this.maxArchivedCount,
    required this.attachmentsQueueTableName,
  }) {
    _context = AttachmentContextImpl(db, log, maxArchivedCount, attachmentsQueueTableName);
  }

  @override
  Stream<void> watchActiveAttachments() async* {
    log.info('Watching attachments...');
    
    // Watch for attachments with active states (queued for upload, download, or delete)
    final stream = db.watch(
      '''
      SELECT 
          id 
      FROM 
          $attachmentsQueueTableName
      WHERE 
          state = ?
          OR state = ?
          OR state = ?
      ORDER BY 
          timestamp ASC
      ''',
      parameters: [
        AttachmentState.queuedUpload.index,
        AttachmentState.queuedDownload.index,
        AttachmentState.queuedDelete.index,
      ],
    );

    yield* stream;
  }

  @override
  Future<T> withContext<T>(Future<T> Function(AttachmentContext ctx) action) {
    // Simple mutex using chained futures
    final completer = Completer<T>();
    _mutex = _mutex.then((_) => action(_context)).then(completer.complete).catchError(completer.completeError);
    return completer.future;
  }
} 