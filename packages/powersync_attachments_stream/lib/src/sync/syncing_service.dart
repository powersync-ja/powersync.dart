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

class SyncingService {
  final RemoteStorage remoteStorage;
  final LocalStorage localStorage;
  final AttachmentService attachmentsService;
  final Future<String> Function(String) getLocalUri;
  final SyncErrorHandler? errorHandler;
  final Duration syncThrottle;
  final Duration period;
  final _log = Logger('SyncingService');

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
  });

  Future<void> startSync() async {
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
              _log.info(
                'active attachments: ${attachments.map((e) => e.id).toList()}',
              );
              _log.info(
                'SyncingService: Found ${attachments.length} active attachments',
              );
              await handleSync(attachments, context);
              await deleteArchivedAttachments(context);
            });
          } catch (e, st) {
            if (e is! StateError && e.toString().contains('cancelled')) {
              _log.severe(
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
      _log.info('Periodically syncing attachments');
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

  Future<void> triggerSync() async {
    if (_isClosed) return;
    _syncTriggerController.add(null);
  }

  Future<void> stopSync() async {
    await _syncSubscription?.cancel();
    await _periodicSubscription?.cancel();
  }

  Future<void> close() async {
    _isClosed = true;
    await stopSync();
    await _syncTriggerController.close();
  }

  Future<void> handleSync(
    List<Attachment> attachments,
    AttachmentContext context,
  ) async {
    _log.info(
      'SyncingService: Starting handleSync with ${attachments.length} attachments',
    );
    final updatedAttachments = <Attachment>[];

    for (final attachment in attachments) {
      _log.info(
        'SyncingService: Processing attachment ${attachment.id} with state: ${attachment.state}',
      );
      try {
        switch (attachment.state) {
          case AttachmentState.queuedDownload:
            _log.info('SyncingService: Downloading [${attachment.filename}]');
            updatedAttachments.add(await downloadAttachment(attachment));
            break;
          case AttachmentState.queuedUpload:
            _log.info('SyncingService: Uploading [${attachment.filename}]');
            updatedAttachments.add(await uploadAttachment(attachment));
            break;
          case AttachmentState.queuedDelete:
            _log.info('SyncingService: Deleting [${attachment.filename}]');
            updatedAttachments.add(await deleteAttachment(attachment));
            break;
          case AttachmentState.synced:
            _log.info(
              'SyncingService: Attachment ${attachment.id} is already synced',
            );
            break;
          case AttachmentState.archived:
            _log.info(
              'SyncingService: Attachment ${attachment.id} is archived',
            );
            break;
        }
      } catch (e, st) {
        _log.warning(
          'SyncingService: Error during sync for ${attachment.id}',
          e,
          st,
        );
      }
    }

    if (updatedAttachments.isNotEmpty) {
      _log.info(
        'SyncingService: Saving ${updatedAttachments.length} updated attachments',
      );
      await context.saveAttachments(updatedAttachments);
    }
  }

  Future<Attachment> uploadAttachment(Attachment attachment) async {
    _log.info(
      'SyncingService: Starting upload for attachment ${attachment.id}',
    );
    try {
      if (attachment.localUri == null) {
        throw Exception('No localUri for attachment $attachment');
      }
      _log.info(
        'SyncingService: Calling remoteStorage.uploadFile for ${attachment.id}',
      );
      await remoteStorage.uploadFile(
        localStorage.readFile(attachment.localUri!),
        attachment,
      );
      _log.info(
        'SyncingService: Successfully uploaded attachment "${attachment.id}" to Cloud Storage',
      );
      return attachment.copyWith(
        state: AttachmentState.synced,
        hasSynced: true,
      );
    } catch (e, st) {
      _log.warning(
        'SyncingService: Upload attachment error for attachment $attachment',
        e,
        st,
      );
      if (errorHandler != null) {
        final shouldRetry = await errorHandler!.onUploadError(attachment, e);
        if (!shouldRetry) {
          _log.info(
            'SyncingService: Attachment with ID ${attachment.id} has been archived',
          );
          return attachment.copyWith(state: AttachmentState.archived);
        }
      }
      return attachment;
    }
  }

  Future<Attachment> downloadAttachment(Attachment attachment) async {
    _log.info(
      'SyncingService: Starting download for attachment ${attachment.id}',
    );
    final attachmentPath = await getLocalUri(attachment.filename);
    try {
      _log.info(
        'SyncingService: Calling remoteStorage.downloadFile for ${attachment.id}',
      );
      final fileStream = await remoteStorage.downloadFile(attachment);
      await localStorage.saveFile(
        attachmentPath,
        fileStream.map((chunk) => Uint8List.fromList(chunk)),
      );
      _log.info(
        'SyncingService: Successfully downloaded file "${attachment.id}"',
      );
      return attachment.copyWith(
        localUri: attachmentPath,
        state: AttachmentState.synced,
        hasSynced: true,
      );
    } catch (e, st) {
      if (errorHandler != null) {
        final shouldRetry = await errorHandler!.onDownloadError(attachment, e);
        if (!shouldRetry) {
          _log.info(
            'SyncingService: Attachment with ID ${attachment.id} has been archived',
          );
          return attachment.copyWith(state: AttachmentState.archived);
        }
      }
      _log.warning(
        'SyncingService: Download attachment error for attachment $attachment',
        e,
        st,
      );
      return attachment;
    }
  }

  Future<Attachment> deleteAttachment(Attachment attachment) async {
    try {
      _log.info(
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
          _log.info('Attachment with ID ${attachment.id} has been archived');
          return attachment.copyWith(state: AttachmentState.archived);
        }
      }
      _log.warning('Error deleting attachment: $e', e, st);
      return attachment;
    }
  }

  Future<bool> deleteArchivedAttachments(AttachmentContext context) async {
    return context.deleteArchivedAttachments((pendingDelete) async {
      for (final attachment in pendingDelete) {
        if (attachment.localUri == null) continue;
        if (!await localStorage.fileExists(attachment.localUri!)) continue;
        await localStorage.deleteFile(attachment.localUri!);
      }
    });
  }
}
