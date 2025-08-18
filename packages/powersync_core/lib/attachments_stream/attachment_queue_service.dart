// Implements the attachment queue for PowerSync attachments.
//
// This class manages the lifecycle of attachment records, including watching for new attachments,
// syncing with remote storage, handling uploads, downloads, and deletes, and managing local storage.
// It provides hooks for error handling, cache management, and custom filename resolution.

import 'dart:async';

import 'package:logging/logging.dart';
import 'package:meta/meta.dart';
import 'package:powersync_core/powersync_core.dart';
import 'package:sqlite_async/sqlite_async.dart';

import 'attachment.dart';
import 'abstractions/attachment_service.dart';
import 'abstractions/attachment_context.dart';
import 'abstractions/local_storage.dart';
import 'abstractions/remote_storage.dart';
import 'abstractions/sync_error_handler.dart';
import 'implementations/attachment_service.dart';
import 'sync/syncing_service.dart';

/// A watched attachment record item.
///
/// This is usually returned from watching all relevant attachment IDs.
///
/// - [id]: Id for the attachment record.
/// - [fileExtension]: File extension used to determine an internal filename for storage if no [filename] is provided.
/// - [filename]: Filename to store the attachment with.
/// - [metaData]: Optional metadata for the attachment record.
@experimental
class WatchedAttachmentItem {
  /// Id for the attachment record.
  final String id;

  /// File extension used to determine an internal filename for storage if no [filename] is provided.
  final String? fileExtension;

  /// Filename to store the attachment with.
  final String? filename;

  /// Optional metadata for the attachment record.
  final String? metaData;

  /// Creates a [WatchedAttachmentItem].
  ///
  /// Either [fileExtension] or [filename] must be provided.
  WatchedAttachmentItem({
    required this.id,
    this.fileExtension,
    this.filename,
    this.metaData,
  }) : assert(
          fileExtension != null || filename != null,
          'Either fileExtension or filename must be provided.',
        );
}

/// Class used to implement the attachment queue.
///
/// Manages the lifecycle of attachment records, including watching for new attachments,
/// syncing with remote storage, handling uploads, downloads, and deletes, and managing local storage.
///
/// Properties:
/// - [db]: PowerSync database client.
/// - [remoteStorage]: Adapter which interfaces with the remote storage backend.
/// - [watchAttachments]: A stream generator for the current state of local attachments.
/// - [localStorage]: Provides access to local filesystem storage methods.
/// - [attachmentsQueueTableName]: SQLite table where attachment state will be recorded.
/// - [errorHandler]: Attachment operation error handler. Specifies if failed attachment operations should be retried.
/// - [syncInterval]: Periodic interval to trigger attachment sync operations.
/// - [archivedCacheLimit]: Defines how many archived records are retained as a cache.
/// - [syncThrottleDuration]: Throttles remote sync operations triggering.
/// - [downloadAttachments]: Should attachments be downloaded.
/// - [logger]: Logging interface used for all log operations.
@experimental
class AttachmentQueue {
  final PowerSyncDatabase db;
  final AbstractRemoteStorageAdapter remoteStorage;
  final Stream<List<WatchedAttachmentItem>> Function() watchAttachments;
  final LocalStorageAdapter localStorage;
  final String attachmentsQueueTableName;
  final SyncErrorHandler? errorHandler;
  final Duration syncInterval;
  final int archivedCacheLimit;
  final Duration syncThrottleDuration;
  final bool downloadAttachments;
  final Logger logger;

  static const String defaultTableName = 'attachments_queue';

  final Mutex _mutex = Mutex();
  bool _closed = false;
  StreamSubscription<List<WatchedAttachmentItem>>? _syncStatusSubscription;
  late final AbstractAttachmentService attachmentsService;
  late final SyncingService syncingService;

  AttachmentQueue({
    required this.db,
    required this.remoteStorage,
    required this.watchAttachments,
    required this.localStorage,
    this.attachmentsQueueTableName = defaultTableName,
    this.errorHandler,
    this.syncInterval = const Duration(seconds: 30),
    this.archivedCacheLimit = 100,
    this.syncThrottleDuration = const Duration(seconds: 1),
    this.downloadAttachments = true,
    Logger? logger,
  }) : logger = logger ?? Logger('AttachmentQueue') {
    attachmentsService = AttachmentServiceImpl(
      db: db,
      logger: this.logger,
      maxArchivedCount: archivedCacheLimit,
      attachmentsQueueTableName: attachmentsQueueTableName,
    );
    syncingService = SyncingService(
      remoteStorage: remoteStorage,
      localStorage: localStorage,
      attachmentsService: attachmentsService,
      errorHandler: errorHandler,
      syncThrottle: syncThrottleDuration,
      period: syncInterval,
    );
  }

  /// Initialize the attachment queue by:
  /// 1. Creating the attachments directory.
  /// 2. Adding watches for uploads, downloads, and deletes.
  /// 3. Adding a trigger to run uploads, downloads, and deletes when the device is online after being offline.
  Future<void> startSync() async {
    await _mutex.lock(() async {
      if (_closed) {
        throw Exception('Attachment queue has been closed');
      }

      await _stopSyncingInternal();

      await localStorage.initialize();

      await attachmentsService.withContext((context) async {
        await _verifyAttachments(context);
      });

      await syncingService.startSync();

      // Listen for connectivity changes and watched attachments
      _syncStatusSubscription = watchAttachments().listen((items) async {
        await _processWatchedAttachments(items);
      });

      logger.info('AttachmentQueue started syncing.');
    });
  }

  /// Stops syncing. Syncing may be resumed with [startSync].
  Future<void> stopSyncing() async {
    await _mutex.lock(() async {
      await _stopSyncingInternal();
    });
  }

  Future<void> _stopSyncingInternal() async {
    if (_closed) return;

    await _syncStatusSubscription?.cancel();
    _syncStatusSubscription = null;
    await syncingService.stopSync();

    logger.info('AttachmentQueue stopped syncing.');
  }

  /// Closes the queue. The queue cannot be used after closing.
  Future<void> close() async {
    await _mutex.lock(() async {
      if (_closed) return;

      await _syncStatusSubscription?.cancel();
      await syncingService.close();
      _closed = true;

      logger.info('AttachmentQueue closed.');
    });
  }

  /// Resolves the filename for new attachment items.
  /// Concatenates the attachment ID and extension by default.
  Future<String> resolveNewAttachmentFilename(
    String attachmentId,
    String? fileExtension,
  ) async {
    return '$attachmentId.${fileExtension ?? 'dat'}';
  }

  /// Processes attachment items returned from [watchAttachments].
  /// The default implementation asserts the items returned from [watchAttachments] as the definitive
  /// state for local attachments.
  Future<void> _processWatchedAttachments(
    List<WatchedAttachmentItem> items,
  ) async {
    await attachmentsService.withContext((context) async {
      final currentAttachments = await context.getAttachments();
      final List<Attachment> attachmentUpdates = [];

      for (final item in items) {
        final existingQueueItem =
            currentAttachments.where((a) => a.id == item.id).firstOrNull;

        if (existingQueueItem == null) {
          if (!downloadAttachments) continue;

          // This item should be added to the queue.
          // This item is assumed to be coming from an upstream sync.
          final String filename = item.filename ??
              await resolveNewAttachmentFilename(item.id, item.fileExtension);

          attachmentUpdates.add(
            Attachment(
              id: item.id,
              filename: filename,
              state: AttachmentState.queuedDownload,
              metaData: item.metaData,
            ),
          );
        } else if (existingQueueItem.state == AttachmentState.archived) {
          // The attachment is present again. Need to queue it for sync.
          if (existingQueueItem.hasSynced) {
            // No remote action required, we can restore the record (avoids deletion).
            attachmentUpdates.add(
              existingQueueItem.copyWith(state: AttachmentState.synced),
            );
          } else {
            // The localURI should be set if the record was meant to be downloaded
            // and has been synced. If it's missing and hasSynced is false then
            // it must be an upload operation.
            attachmentUpdates.add(
              existingQueueItem.copyWith(
                state: existingQueueItem.localUri == null
                    ? AttachmentState.queuedDownload
                    : AttachmentState.queuedUpload,
              ),
            );
          }
        }
      }

      // Archive any items not specified in the watched items.
      // For queuedDelete or queuedUpload states, archive only if hasSynced is true.
      // For other states, archive if the record is not found in the items.
      for (final attachment in currentAttachments) {
        final notInWatchedItems = items.every(
          (update) => update.id != attachment.id,
        );

        if (notInWatchedItems) {
          switch (attachment.state) {
            case AttachmentState.queuedDelete:
            case AttachmentState.queuedUpload:
              if (attachment.hasSynced) {
                attachmentUpdates.add(
                  attachment.copyWith(state: AttachmentState.archived),
                );
              }
            default:
              attachmentUpdates.add(
                attachment.copyWith(state: AttachmentState.archived),
              );
          }
        }
      }

      await context.saveAttachments(attachmentUpdates);
    });
  }

  /// Creates a new attachment locally and queues it for upload.
  /// The filename is resolved using [resolveNewAttachmentFilename].
  Future<Attachment> saveFile({
    required List<int> data,
    required String mediaType,
    String? fileExtension,
    String? metaData,
    required Future<void> Function(
            SqliteWriteContext context, Attachment attachment)
        updateHook,
  }) async {
    final row = await db.get('SELECT uuid() as id');
    final id = row['id'] as String;
    final String filename = await resolveNewAttachmentFilename(
      id,
      fileExtension,
    );

    // Write the file to the filesystem.
    final fileSize = await localStorage.saveFile(filename, data);

    return await attachmentsService.withContext((attachmentContext) async {
      return await db.writeTransaction((tx) async {
        final attachment = Attachment(
          id: id,
          filename: filename,
          size: fileSize,
          mediaType: mediaType,
          state: AttachmentState.queuedUpload,
          localUri: filename,
          metaData: metaData,
        );

        // Allow consumers to set relationships to this attachment ID.
        await updateHook(tx, attachment);

        return await attachmentContext.upsertAttachment(attachment, tx);
      });
    });
  }

  /// Queues an attachment for delete.
  /// The default implementation assumes the attachment record already exists locally.
  Future<Attachment> deleteFile({
    required String attachmentId,
    required Future<void> Function(
            SqliteWriteContext context, Attachment attachment)
        updateHook,
  }) async {
    return await attachmentsService.withContext((attachmentContext) async {
      final attachment = await attachmentContext.getAttachment(attachmentId);
      if (attachment == null) {
        throw Exception(
          'Attachment record with id $attachmentId was not found.',
        );
      }

      return await db.writeTransaction((tx) async {
        await updateHook(tx, attachment);
        return await attachmentContext.upsertAttachment(
          attachment.copyWith(
            state: AttachmentState.queuedDelete,
            hasSynced: false,
          ),
          tx,
        );
      });
    });
  }

  /// Removes all archived items.
  Future<void> expireCache() async {
    await attachmentsService.withContext((context) async {
      bool done;
      do {
        done = await syncingService.deleteArchivedAttachments(context);
      } while (!done);
    });
  }

  /// Clears the attachment queue and deletes all attachment files.
  Future<void> clearQueue() async {
    await attachmentsService.withContext((context) async {
      await context.clearQueue();
    });
    await localStorage.clear();
  }

  /// Cleans up stale attachments.
  Future<void> _verifyAttachments(AbstractAttachmentContext context) async {
    final attachments = await context.getActiveAttachments();
    final List<Attachment> updates = [];

    for (final attachment in attachments) {
      // Only check attachments that should have local files
      if (attachment.localUri == null) {
        // Skip attachments that don't have localUri (like queued downloads)
        continue;
      }

      final exists = await localStorage.fileExists(attachment.localUri!);
      if ((attachment.state == AttachmentState.synced ||
              attachment.state == AttachmentState.queuedUpload) &&
          !exists) {
        updates.add(
          attachment.copyWith(state: AttachmentState.archived, localUri: null),
        );
      }
    }

    await context.saveAttachments(updates);
  }
}
