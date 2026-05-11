import 'dart:async';

import 'package:meta/meta.dart';
import 'package:logging/logging.dart';
import 'package:async/async.dart';

import '../attachment.dart';
import '../implementations/attachment_context.dart';
import '../implementations/attachment_service.dart';
import '../local_storage.dart';
import '../remote_storage.dart';
import '../sync_error_handler.dart';

/// SyncingService is responsible for syncing attachments between local and remote storage.
///
/// This service handles downloading, uploading, and deleting attachments, as well as
/// periodically syncing attachment states. It ensures proper lifecycle management
/// of sync operations and provides mechanisms for error handling and retries.
///
/// Properties:
/// - [remoteStorage]: The remote storage implementation for handling file operations.
/// - [localStorage]: The local storage implementation for managing files locally.
/// - [attachmentsService]: The service for managing attachment states and operations.
/// - [errorHandler]: Optional error handler for managing sync-related errors.
@internal
final class SyncingService {
  final RemoteStorage remoteStorage;
  final LocalStorage localStorage;
  final AttachmentService attachmentsService;
  final AttachmentErrorHandler? errorHandler;
  final Duration syncThrottle;
  final Duration period;
  final Logger logger;

  StreamSubscription<void>? _syncSubscription;
  StreamSubscription<void>? _periodicSubscription;
  bool _isClosed = false;
  final _syncTriggerController = StreamController<void>.broadcast();

  SyncingService({
    required this.remoteStorage,
    required this.localStorage,
    required this.attachmentsService,
    this.errorHandler,
    this.syncThrottle = const Duration(seconds: 5),
    this.period = const Duration(seconds: 30),
    required this.logger,
  });

  /// Starts the syncing process, including periodic and event-driven sync operations.
  Future<void> startSync() async {
    if (_isClosed) return;

    _syncSubscription?.cancel();
    _periodicSubscription?.cancel();

    // Create a merged stream of manual triggers and attachment changes
    final attachmentChanges = attachmentsService.watchActiveAttachments(
      throttle: syncThrottle,
    );
    final manualTriggers = _syncTriggerController.stream;

    late StreamSubscription<void> sub;
    final syncStream =
        StreamGroup.merge<void>([attachmentChanges, manualTriggers])
            .takeWhile((_) => sub == _syncSubscription)
            .asyncMap((_) async {
      // Read the active set inside the mutex; release it before doing any
      // per-attachment I/O so that concurrent `saveFile`/`deleteFile` and
      // `_processWatchedAttachments` calls aren't blocked for the duration
      // of the whole batch.
      final attachments = await attachmentsService.withContext(
        (context) => context.getActiveAttachments(),
      );
      logger.info('Found ${attachments.length} active attachments');

      await handleSync(
        attachments,
        isActive: () => sub == _syncSubscription,
      );

      await attachmentsService.withContext(deleteArchivedAttachments);
    });

    _syncSubscription = sub = syncStream.listen(null);

    // Start periodic sync using instance period
    _periodicSubscription = Stream<void>.periodic(period, (_) {}).listen((
      _,
    ) {
      logger.info('Periodically syncing attachments');
      triggerSync();
    });
  }

  /// Enqueues a sync operation (manual trigger).
  void triggerSync() {
    if (!_isClosed) _syncTriggerController.add(null);
  }

  /// Stops all ongoing sync operations.
  Future<void> stopSync() async {
    await _periodicSubscription?.cancel();

    final subscription = _syncSubscription;
    // Add a trigger event after clearing the subscription, which will make
    // the takeWhile() callback cancel. This allows us to use asFuture() here,
    // ensuring that we only complete this future when the stream is actually
    // done.
    _syncSubscription = null;
    _syncTriggerController.add(null);
    await subscription?.asFuture<void>();
  }

  /// Closes the syncing service, stopping all operations and releasing resources.
  Future<void> close() async {
    _isClosed = true;
    await stopSync();
    await _syncTriggerController.close();
  }

  /// Handles syncing operations for a list of attachments, including
  /// downloading, uploading, and deleting files based on their states.
  ///
  /// Each attachment's I/O runs outside the attachment-service mutex, and the
  /// row's state transition is persisted immediately after it completes. This
  /// keeps the mutex available to concurrent `saveFile` / `deleteFile` /
  /// watched-attachment processing while a batch is in flight, and means
  /// consumer queries against the attachments queue see incremental progress
  /// instead of one atomic commit at the end of the batch.
  ///
  /// [attachments]: The list of attachments to process.
  /// [isActive]: Polled between attachments; when it returns `false` the loop
  /// exits early. Used by `stopSync` to interrupt a running batch within one
  /// attachment's processing time.
  Future<void> handleSync(
    List<Attachment> attachments, {
    bool Function()? isActive,
  }) async {
    logger.info('Starting handleSync with ${attachments.length} attachments');

    for (final attachment in attachments) {
      if (isActive != null && !isActive()) {
        logger.info('Sync cancelled; stopping iteration early');
        return;
      }

      logger.info(
        'Processing attachment ${attachment.id} with state: ${attachment.state}',
      );

      Attachment? updated;
      try {
        switch (attachment.state) {
          case AttachmentState.queuedDownload:
            logger.info('Downloading [${attachment.filename}]');
            updated = await downloadAttachment(attachment);
            break;
          case AttachmentState.queuedUpload:
            logger.info('Uploading [${attachment.filename}]');
            updated = await uploadAttachment(attachment);
            break;
          case AttachmentState.queuedDelete:
            logger.info('Deleting [${attachment.filename}]');
            // `deleteAttachment` needs a context (it removes the row in a
            // transaction); briefly re-acquire the mutex for just this row.
            updated = await attachmentsService.withContext(
              (context) => deleteAttachment(attachment, context),
            );
            break;
          case AttachmentState.synced:
            logger.info('Attachment ${attachment.id} is already synced');
            continue;
          case AttachmentState.archived:
            logger.info('Attachment ${attachment.id} is archived');
            continue;
        }
      } catch (e, st) {
        logger.warning('Error during sync for ${attachment.id}', e, st);
        continue;
      }

      if (updated != null) {
        await attachmentsService.withContext(
          (context) => context.saveAttachments([updated!]),
        );
      }
    }
  }

  /// Uploads an attachment from local storage to remote storage.
  ///
  /// [attachment]: The attachment to upload.
  /// Returns the updated attachment with its new state.
  Future<Attachment> uploadAttachment(Attachment attachment) async {
    logger.info('Starting upload for attachment ${attachment.id}');
    try {
      if (attachment.localUri == null) {
        throw Exception('No localUri for attachment $attachment');
      }
      await remoteStorage.uploadFile(
        localStorage.readFile(attachment.localUri!),
        attachment,
      );
      logger.info(
        'Successfully uploaded attachment "${attachment.id}" to Cloud Storage',
      );
      return attachment.copyWith(
        state: AttachmentState.synced,
        hasSynced: true,
      );
    } catch (e, st) {
      logger.warning(
        'Upload attachment error for attachment $attachment',
        e,
        st,
      );
      if (errorHandler != null) {
        final shouldRetry =
            await errorHandler!.onUploadError(attachment, e, st);
        if (!shouldRetry) {
          logger.info('Attachment with ID ${attachment.id} has been archived');
          return attachment.copyWith(state: AttachmentState.archived);
        }
      }
      return attachment;
    }
  }

  /// Downloads an attachment from remote storage and saves it to local storage.
  ///
  /// [attachment]: The attachment to download.
  /// Returns the updated attachment with its new state.
  Future<Attachment> downloadAttachment(Attachment attachment) async {
    logger.info('Starting download for attachment ${attachment.id}');
    final attachmentPath = attachment.filename;
    try {
      final fileStream = await remoteStorage.downloadFile(attachment);
      await localStorage.saveFile(attachmentPath, fileStream);
      logger.info('Successfully downloaded file "${attachment.id}"');

      return attachment.copyWith(
        localUri: attachmentPath,
        state: AttachmentState.synced,
        hasSynced: true,
      );
    } catch (e, st) {
      if (errorHandler != null) {
        final shouldRetry =
            await errorHandler!.onDownloadError(attachment, e, st);
        if (!shouldRetry) {
          logger.info('Attachment with ID ${attachment.id} has been archived');
          return attachment.copyWith(state: AttachmentState.archived);
        }
      }
      logger.warning(
        'Download attachment error for attachment $attachment',
        e,
        st,
      );
      return attachment;
    }
  }

  /// Deletes an attachment from remote and local storage, and removes it from the queue.
  ///
  /// [attachment]: The attachment to delete.
  /// Returns the updated attachment with its new state.
  Future<Attachment> deleteAttachment(
      Attachment attachment, AttachmentContext context) async {
    try {
      logger.info('Deleting attachment ${attachment.id} from remote storage');
      await remoteStorage.deleteFile(attachment);

      if (attachment.localUri != null &&
          await localStorage.fileExists(attachment.localUri!)) {
        await localStorage.deleteFile(attachment.localUri!);
      }
      // Remove the attachment record from the queue in a transaction.
      await context.deleteAttachment(attachment.id);
      return attachment.copyWith(state: AttachmentState.archived);
    } catch (e, st) {
      if (errorHandler != null) {
        final shouldRetry =
            await errorHandler!.onDeleteError(attachment, e, st);
        if (!shouldRetry) {
          logger.info('Attachment with ID ${attachment.id} has been archived');
          return attachment.copyWith(state: AttachmentState.archived);
        }
      }
      logger.warning('Error deleting attachment: $e', e, st);
      return attachment;
    }
  }

  /// Deletes archived attachments from local storage.
  ///
  /// [context]: The attachment context used to retrieve and manage archived attachments.
  /// Returns `true` if all archived attachments were successfully deleted, `false` otherwise.
  Future<bool> deleteArchivedAttachments(
    AttachmentContext context,
  ) async {
    return context.deleteArchivedAttachments((pendingDelete) async {
      for (final attachment in pendingDelete) {
        if (attachment.localUri == null) continue;
        if (!await localStorage.fileExists(attachment.localUri!)) continue;
        await localStorage.deleteFile(attachment.localUri!);
      }
    });
  }
}
