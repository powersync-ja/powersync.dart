import 'dart:async';
import 'package:logging/logging.dart';
import 'package:powersync_core/powersync_core.dart';
import 'package:sqlite_async/sqlite_async.dart';

import '../abstractions/attachment_service.dart';
import '../abstractions/attachment_context.dart';
import '../attachment.dart';
import 'attachment_context.dart';

class AttachmentServiceImpl implements AbstractAttachmentService {
  final PowerSyncDatabase db;
  final Logger logger;
  final int maxArchivedCount;
  final String attachmentsQueueTableName;
  final Mutex _mutex = Mutex();

  late final AbstractAttachmentContext _context;

  AttachmentServiceImpl({
    required this.db,
    required this.logger,
    required this.maxArchivedCount,
    required this.attachmentsQueueTableName,
  }) {
    _context = AttachmentContextImpl(
      db,
      logger,
      maxArchivedCount,
      attachmentsQueueTableName,
    );
  }

  @override
  Stream<void> watchActiveAttachments() async* {
    logger.info('Watching attachments...');

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
  Future<T> withContext<T>(
    Future<T> Function(AbstractAttachmentContext ctx) action,
  ) async {
    return await _mutex.lock(() async {
      try {
        return await action(_context);
      } catch (e, stackTrace) {
        // Re-throw the error to be handled by the caller
        Error.throwWithStackTrace(e, stackTrace);
      }
    });
  }
}
