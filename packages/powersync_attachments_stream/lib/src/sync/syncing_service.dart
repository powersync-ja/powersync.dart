// Service responsible for syncing attachments between local and remote storage.
//
// This service handles downloading, uploading, and deleting attachments, as well as
// periodically syncing attachment states. It ensures proper lifecycle management
// of sync operations and provides mechanisms for error handling and retries.
//
// The class provides a default implementation for syncing operations, which can be
// extended or customized as needed.

import 'dart:async';
import 'dart:typed_data';
import 'package:logging/logging.dart';
import 'package:async/async.dart';

import '../abstractions/attachment_service.dart';
import '../abstractions/attachment_context.dart';
import '../attachment.dart';
import '../abstractions/local_storage.dart';
import '../abstractions/remote_storage.dart';
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
/// - [getLocalUri]: A function to resolve the local URI for a given filename.
/// - [onDownloadError], [onUploadError], [onDeleteError]: Optional error handlers for managing sync-related errors.
class SyncingService {
  final AbstractRemoteStorageAdapter remoteStorage;
  final AbstractLocalStorageAdapter localStorage;
  final AbstractAttachmentService attachmentsService;
  final Future<String> Function(String) getLocalUri;
  final SyncErrorHandler? errorHandler;
  final Duration syncThrottle;
  final Duration period;
  final Logger logger;

  StreamSubscription? _syncSubscription;
  StreamSubscription? _periodicSubscription;
  bool _isClosed = false;
  final _syncTriggerController = StreamController<void>.broadcast();

  SyncingService({
    required this.remoteStorage,
    required this.localStorage,
    required this.attachmentsService,
    required this.getLocalUri,
    this.errorHandler,
    this.syncThrottle = const Duration(seconds: 5),
    this.period = const Duration(seconds: 30),
    Logger? logger,
  }) : logger = logger ?? Logger('SyncingService');

  /// Starts the syncing process, including periodic and event-driven sync operations.
  ///
  /// [period] is the interval at which periodic sync operations are triggered.
  Future<void> startSync({Duration period = const Duration(seconds: 30)}) async {
    if (_isClosed) return;

    _syncSubscription?.cancel();
    _periodicSubscription?.cancel();

    // Create a merged stream of manual triggers and attachment changes
    final attachmentChanges = attachmentsService.watchActiveAttachments();
    final manualTriggers = _syncTriggerController.stream;

    // Merge both streams and apply throttling
    final mergedStream = StreamGroup.merge([attachmentChanges, manualTriggers])
        .transform(_throttleTransformer(syncThrottle))
        .listen((_) async {
          try {
            await attachmentsService.withContext((context) async {
              final attachments = await context.getActiveAttachments();
              logger.info(
                'active attachments: ${attachments.map((e) => e.id).toList()}',
              );
              logger.info(
                'SyncingService: Found ${attachments.length} active attachments',
              );
              await handleSync(attachments, context);
              await deleteArchivedAttachments(context);
            });
          } catch (e, st) {
            if (e is! StateError && e.toString().contains('cancelled')) {
              logger.severe(
                'Caught exception when processing attachments',
                e,
                st,
              );
            } else {
              rethrow;
            }
          }
        });

    _syncSubscription = mergedStream;

    // Start periodic sync
    _periodicSubscription = Stream.periodic(period).listen((_) {
      logger.info('Periodically syncing attachments');
      triggerSync();
    });
  }

  StreamTransformer<T, T> _throttleTransformer<T>(Duration throttle) {
    return StreamTransformer.fromHandlers(
      handleData: (data, sink) {
        sink.add(data);
        // Simple throttle implementation - just delay the next event
        Future.delayed(throttle);
      },
    );
  }

  /// Enqueues a sync operation (manual trigger).
  Future<void> triggerSync() async {
    if (_isClosed) return;
    _syncTriggerController.add(null);
  }

  /// Stops all ongoing sync operations.
  Future<void> stopSync() async {
    await _syncSubscription?.cancel();
    await _periodicSubscription?.cancel();
  }

  /// Closes the syncing service, stopping all operations and releasing resources.
  Future<void> close() async {
    _isClosed = true;
    await stopSync();
    await _syncTriggerController.close();
  }

  /// Handles syncing operations for a list of attachments, including downloading,
  /// uploading, and deleting files based on their states.
  ///
  /// [attachments]: The list of attachments to process.
  /// [context]: The attachment context used for managing attachment states.
  Future<void> handleSync(
    List<Attachment> attachments,
    AbstractAttachmentContext context,
  ) async {
    logger.info(
      'SyncingService: Starting handleSync with ${attachments.length} attachments',
    );
    final updatedAttachments = <Attachment>[];

    for (final attachment in attachments) {
      logger.info(
        'SyncingService: Processing attachment ${attachment.id} with state: ${attachment.state}',
      );
      try {
        switch (attachment.state) {
          case AttachmentState.queuedDownload:
            logger.info('SyncingService: Downloading [${attachment.filename}]');
            updatedAttachments.add(await downloadAttachment(attachment));
            break;
          case AttachmentState.queuedUpload:
            logger.info('SyncingService: Uploading [${attachment.filename}]');
            updatedAttachments.add(await uploadAttachment(attachment));
            break;
          case AttachmentState.queuedDelete:
            logger.info('SyncingService: Deleting [${attachment.filename}]');
            updatedAttachments.add(await deleteAttachment(attachment));
            break;
          case AttachmentState.synced:
            logger.info(
              'SyncingService: Attachment ${attachment.id} is already synced',
            );
            break;
          case AttachmentState.archived:
            logger.info(
              'SyncingService: Attachment ${attachment.id} is archived',
            );
            break;
        }
      } catch (e, st) {
        logger.warning(
          'SyncingService: Error during sync for ${attachment.id}',
          e,
          st,
        );
      }
    }

    if (updatedAttachments.isNotEmpty) {
      logger.info(
        'SyncingService: Saving ${updatedAttachments.length} updated attachments',
      );
      await context.saveAttachments(updatedAttachments);
    }
  }

  /// Uploads an attachment from local storage to remote storage.
  ///
  /// [attachment]: The attachment to upload.
  /// Returns the updated attachment with its new state.
  Future<Attachment> uploadAttachment(Attachment attachment) async {
    logger.info(
      'SyncingService: Starting upload for attachment ${attachment.id}',
    );
    try {
      if (attachment.localUri == null) {
        throw Exception('No localUri for attachment $attachment');
      }
      await remoteStorage.uploadFile(
        localStorage.readFile(attachment.localUri!),
        attachment,
      );
      logger.info(
        'SyncingService: Successfully uploaded attachment "${attachment.id}" to Cloud Storage',
      );
      return attachment.copyWith(
        state: AttachmentState.synced,
        hasSynced: true,
      );
    } catch (e, st) {
      logger.warning(
        'SyncingService: Upload attachment error for attachment $attachment',
        e,
        st,
      );
      if (errorHandler != null) {
        final shouldRetry = await errorHandler!.onUploadError(attachment, e);
        if (!shouldRetry) {
          logger.info(
            'SyncingService: Attachment with ID ${attachment.id} has been archived',
          );
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
    logger.info(
      'SyncingService: Starting download for attachment ${attachment.id}',
    );
    final attachmentPath = await getLocalUri(attachment.filename);
    try {
      final fileStream = await remoteStorage.downloadFile(attachment);
      await localStorage.saveFile(
        attachmentPath,
        fileStream.map((chunk) => Uint8List.fromList(chunk)),
      );
      logger.info(
        'SyncingService: Successfully downloaded file "${attachment.id}"',
      );

      logger.info('downloadAttachmentXY $attachment');

      return attachment.copyWith(
        localUri: attachmentPath,
        state: AttachmentState.synced,
        hasSynced: true,
      );
    } catch (e, st) {
      if (errorHandler != null) {
        final shouldRetry = await errorHandler!.onDownloadError(attachment, e);
        if (!shouldRetry) {
          logger.info(
            'SyncingService: Attachment with ID ${attachment.id} has been archived',
          );
          return attachment.copyWith(state: AttachmentState.archived);
        }
      }
      logger.warning(
        'SyncingService: Download attachment error for attachment $attachment',
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
  Future<Attachment> deleteAttachment(Attachment attachment) async {
    try {
      logger.info(
        'SyncingService: Deleting attachment ${attachment.id} from remote storage',
      );
      await remoteStorage.deleteFile(attachment);

      if (attachment.localUri != null &&
          await localStorage.fileExists(attachment.localUri!)) {
        await localStorage.deleteFile(attachment.localUri!);
      }
      return attachment.copyWith(state: AttachmentState.archived);
    } catch (e, st) {
      if (errorHandler != null) {
        final shouldRetry = await errorHandler!.onDeleteError(attachment, e);
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
  Future<bool> deleteArchivedAttachments(AbstractAttachmentContext context) async {
    return context.deleteArchivedAttachments((pendingDelete) async {
      for (final attachment in pendingDelete) {
        if (attachment.localUri == null) continue;
        if (!await localStorage.fileExists(attachment.localUri!)) continue;
        await localStorage.deleteFile(attachment.localUri!);
      }
    });
  }
}
