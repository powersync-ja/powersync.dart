import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import './attachments_queue.dart';
import './local_storage_adapter.dart';
import './remote_storage_adapter.dart';
import 'package:powersync/powersync.dart';
import 'attachments_queue_table.dart';
import 'attachments_service.dart';

/// Service used to sync attachments between local and remote storage
class SyncingService {
  final PowerSyncDatabase db;
  final AbstractRemoteStorageAdapter remoteStorage;
  final LocalStorageAdapter localStorage;
  final AttachmentsService attachmentsService;
  final Function getLocalUri;
  final Future<bool> Function(Attachment attachment, Object exception)?
      onDownloadError;
  final Future<bool> Function(Attachment attachment, Object exception)?
      onUploadError;
  bool isProcessing = false;
  Timer? timer;

  SyncingService(this.db, this.remoteStorage, this.localStorage,
      this.attachmentsService, this.getLocalUri,
      {this.onDownloadError, this.onUploadError});

  /// Upload attachment from local storage and to remote storage
  /// then remove it from the queue.
  /// If duplicate of the file is found uploading is archived and
  /// the attachment is removed from the queue.
  Future<void> uploadAttachment(Attachment attachment) async {
    if (attachment.localUri == null) {
      throw Exception('No localUri for attachment $attachment');
    }

    String imagePath = await getLocalUri(attachment.filename);

    try {
      await remoteStorage.uploadFile(attachment.filename, File(imagePath),
          mediaType: attachment.mediaType!);
      await attachmentsService.deleteAttachment(attachment.id);
      log.info('Uploaded attachment "${attachment.id}" to Cloud Storage');
      return;
    } catch (e) {
      if (e.toString().contains('Duplicate')) {
        log.warning('File already uploaded, deleting ${attachment.id}');
        await attachmentsService.deleteAttachment(attachment.id);
        return;
      }

      log.severe('Upload attachment error for attachment $attachment', e);
      if (onUploadError != null) {
        bool shouldRetry = await onUploadError!(attachment, e);
        if (!shouldRetry) {
          log.info('Attachment with ID ${attachment.id} has been archived', e);
          await attachmentsService.ignoreAttachment(attachment.id);
        }
      }

      return;
    }
  }

  /// Download attachment from remote storage and save it to local storage
  /// then remove it from the queue.
  Future<void> downloadAttachment(Attachment attachment) async {
    String imagePath = await getLocalUri(attachment.filename);

    try {
      Uint8List fileBlob =
          await remoteStorage.downloadFile(attachment.filename);

      await localStorage.saveFile(imagePath, fileBlob);

      log.info('Downloaded file "${attachment.id}"');
      await attachmentsService.deleteAttachment(attachment.id);
      return;
    } catch (e) {
      if (onDownloadError != null) {
        bool shouldRetry = await onDownloadError!(attachment, e);
        if (!shouldRetry) {
          log.info('Attachment with ID ${attachment.id} has been archived', e);
          await attachmentsService.ignoreAttachment(attachment.id);
          return;
        }
      }

      log.severe('Download attachment error for attachment $attachment', e);
      return;
    }
  }

  /// Delete attachment from remote, local storage and then remove it from the queue.
  Future<void> deleteAttachment(Attachment attachment) async {
    String fileUri = await getLocalUri(attachment.filename);
    try {
      await remoteStorage.deleteFile(attachment.filename);
      await localStorage.deleteFile(fileUri);
      await attachmentsService.deleteAttachment(attachment.id);
      log.info('Deleted attachment "${attachment.id}"');
    } catch (e) {
      log.severe(e);
    }
  }

  /// Handle downloading, uploading or deleting of attachments
  Future<void> handleSync(Iterable<Attachment> attachments) async {
      if (isProcessing == true) {
        return;
      }
  
    try {
      isProcessing = true;

      for (Attachment attachment in attachments) {
        if (AttachmentState.queuedDownload.index == attachment.state) {
          log.info('Downloading ${attachment.filename}');
          await downloadAttachment(attachment);
        }
        if (AttachmentState.queuedUpload.index == attachment.state) {
          log.info('Uploading ${attachment.filename}');
          await uploadAttachment(attachment);
        }
        if (AttachmentState.queuedDelete.index == attachment.state) {
          log.info('Deleting ${attachment.filename}');
          await deleteAttachment(attachment);
        }
      }
    } finally {
      // if anything throws an exception
      // reset the ability to sync
      isProcessing = false;
    }
  }

  /// Watcher for changes to attachments table
  /// Once a change is detected it will initiate a sync of the attachments
  StreamSubscription<void> watchAttachments() {
    log.info('Watching attachments...');
    return db.watch('''
      SELECT * FROM ${attachmentsService.table}
      WHERE state != ${AttachmentState.archived.index}
    ''').map((results) {
      return results.map((row) => Attachment.fromRow(row));
    }).listen((attachments) async {
      await handleSync(attachments);
    });
  }

  /// Run the sync process on all attachments
  Future<void> runSync() async {
    List<Attachment> attachments = await db.execute('''
      SELECT * FROM ${attachmentsService.table}
      WHERE state != ${AttachmentState.archived.index}
    ''').then((results) {
      return results.map((row) => Attachment.fromRow(row)).toList();
    });

    await handleSync(attachments);
  }

  /// Process ID's to be included in the attachment queue.
  processIds(List<String> ids, String fileExtension) async {
    List<Attachment> attachments = List.empty(growable: true);

    for (String id in ids) {
      String path = await getLocalUri('$id.$fileExtension');
      File file = File(path);
      bool fileExists = await file.exists();

      if (fileExists) {
        continue;
      }

      log.info('Adding $id to queue');
      attachments.add(Attachment(
          id: id,
          filename: '$id.$fileExtension',
          state: AttachmentState.queuedDownload.index));
    }

    await attachmentsService.saveAttachments(attachments);
  }

  /// Delete attachments which have been archived
  deleteArchivedAttachments() async {
    await db.execute('''
      DELETE FROM ${attachmentsService.table}
      WHERE state = ${AttachmentState.archived.index}
    ''');
  }

  /// Periodically sync attachments and delete archived attachments
  void startPeriodicSync(int intervalInMinutes) {
    timer?.cancel();

    timer = Timer.periodic(Duration(minutes: intervalInMinutes), (timer) {
      log.info('Syncing attachments');
      runSync();
      log.info('Deleting archived attachments');
      deleteArchivedAttachments();
    });
  }
}
