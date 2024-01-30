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

  SyncingService(this.db, this.remoteStorage, this.localStorage,
      this.attachmentsService, this.getLocalUri);

  /// Upload attachment from local storage and to remote storage
  /// then remove it from the queue.
  /// If duplicate of the file is found uploading is ignored and
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
      log.severe('Download attachment error for attachment $attachment}', e);
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

  /// Function to manually run downloads for attachments marked for download
  /// in the attachment queue.
  /// Once a an attachment marked for download is found it will initiate a
  /// download of the file to local storage.
  StreamSubscription<void> watchDownloads() {
    log.info('Watching downloads...');
    return db.watch('''
      SELECT * FROM ${attachmentsService.table}
      WHERE state = ${AttachmentState.queuedDownload.index}
    ''').map((results) {
      return results.map((row) => Attachment.fromRow(row));
    }).listen((attachments) async {
      for (Attachment attachment in attachments) {
        log.info('Downloading ${attachment.filename}');
        await downloadAttachment(attachment);
      }
    });
  }

  /// Watcher for attachments marked for download in the attachment queue.
  /// Once a an attachment marked for download is found it will initiate a
  /// download of the file to local storage.
  Future<void> runDownloads() async {
    List<Attachment> attachments = await db.execute('''
      SELECT * FROM ${attachmentsService.table}
      WHERE state = ${AttachmentState.queuedDownload.index}
    ''').then((results) {
      return results.map((row) => Attachment.fromRow(row)).toList();
    });

    for (Attachment attachment in attachments) {
      log.info('Downloading ${attachment.filename}');
      await downloadAttachment(attachment);
    }
  }

  /// Watcher for attachments marked for upload in the attachment queue.
  /// Once a an attachment marked for upload is found it will initiate an
  /// upload of the file to remote storage.
  StreamSubscription<void> watchUploads() {
    log.info('Watching uploads...');
    return db.watch('''
      SELECT * FROM ${attachmentsService.table}
      WHERE local_uri IS NOT NULL
      AND state = ${AttachmentState.queuedUpload.index}
    ''').map((results) {
      return results.map((row) => Attachment.fromRow(row));
    }).listen((attachments) async {
      for (Attachment attachment in attachments) {
        log.info('Uploading ${attachment.filename}');
        await uploadAttachment(attachment);
      }
    });
  }

  /// Function to manually run uploads for attachments marked for upload
  /// in the attachment queue.
  /// Once a an attachment marked for deletion is found it will initiate an
  /// upload of the file to remote storage
  Future<void> runUploads() async {
    List<Attachment> attachments = await db.execute('''
      SELECT * FROM ${attachmentsService.table}
      WHERE local_uri IS NOT NULL
      AND state = ${AttachmentState.queuedUpload.index}
    ''').then((results) {
      return results.map((row) => Attachment.fromRow(row)).toList();
    });

    for (Attachment attachment in attachments) {
      log.info('Uploading ${attachment.filename}');
      await uploadAttachment(attachment);
    }
  }

  /// Watcher for attachments marked for deletion in the attachment queue.
  /// Once a an attachment marked for deletion is found it will initiate remote
  /// and local deletions of the file.
  StreamSubscription<void> watchDeletes() {
    log.info('Watching deletes...');
    return db.watch('''
      SELECT * FROM ${attachmentsService.table}
      WHERE state = ${AttachmentState.queuedDelete.index}
    ''').map((results) {
      return results.map((row) => Attachment.fromRow(row));
    }).listen((attachments) async {
      for (Attachment attachment in attachments) {
        log.info('Deleting ${attachment.filename}');
        await deleteAttachment(attachment);
      }
    });
  }

  /// Function to manually run deletes for attachments marked for deletion
  /// in the attachment queue.
  /// Once a an attachment marked for deletion is found it will initiate remote
  /// and local deletions of the file.
  Future<void> runDeletes() async {
    List<Attachment> attachments = await db.execute('''
      SELECT * FROM ${attachmentsService.table}
      WHERE state = ${AttachmentState.queuedDelete.index}
    ''').then((results) {
      return results.map((row) => Attachment.fromRow(row)).toList();
    });

    for (Attachment attachment in attachments) {
      log.info('Deleting ${attachment.filename}');
      await deleteAttachment(attachment);
    }
  }

  /// Reconcile an ID with ID's in the attachment queue.
  /// If the ID is not in the queue, but the file exists locally then it is
  /// in local and remote storage.
  /// If the ID is in the queue, but the file does not exist locally then it is
  /// marked for download.
  reconcileId(String id, List<String> idsInQueue, String fileExtension) async {
    bool idIsInQueue = idsInQueue.contains(id);

    String path = await getLocalUri('$id.$fileExtension');
    File file = File(path);
    bool fileExists = await file.exists();

    if (!idIsInQueue) {
      if (fileExists) {
        log.info('ignore file $id.$fileExtension as it already exists');
        return;
      }
      log.info('Adding $id to queue');
      return await attachmentsService.saveAttachment(Attachment(
        id: id,
        filename: '$id.$fileExtension',
        state: AttachmentState.queuedDownload.index,
      ));
    }
  }
}
