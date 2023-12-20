import 'dart:async';

import 'package:powersync/powersync.dart';
import 'package:powersync_attachments_helper/powersync_attachments_helper.dart';
import 'package:powersync_flutter_demo/app_config.dart';
import 'package:powersync_flutter_demo/attachments/remote_storage_adapter.dart';

import 'package:powersync_flutter_demo/models/schema.dart';

/// Global reference to the queue
late final PhotoAttachmentQueue attachmentQueue;
final remoteStorage = SupabaseStorageAdapter();

class PhotoAttachmentQueue extends AbstractAttachmentQueue {
  PhotoAttachmentQueue(db, remoteStorage)
      : super(db: db, remoteStorage: remoteStorage);

  @override
  init() async {
    if (AppConfig.supabaseStorageBucket.isEmpty) {
      log.info(
          'No Supabase bucket configured, skip setting up PhotoAttachmentQueue watches');
      return;
    }

    await super.init();
  }

  @override
  Future<Attachment> savePhoto(String photoId, int size) async {
    String filename = '$photoId.jpg';
    Attachment photoAttachment = Attachment(
      id: photoId,
      filename: filename,
      state: AttachmentState.queuedUpload.index,
      mediaType: 'image/jpeg',
      localUri: getLocalFilePathSuffix(filename),
      size: size,
    );

    return attachmentsService.saveAttachment(photoAttachment);
  }

  @override
  Future<Attachment> deletePhoto(String photoId) async {
    String filename = '$photoId.jpg';
    Attachment photoAttachment = Attachment(
        id: photoId,
        filename: filename,
        state: AttachmentState.queuedDelete.index);

    return attachmentsService.saveAttachment(photoAttachment);
  }

  @override
  StreamSubscription<void> watchIds() {
    log.info('Watching photos in $todosTable...');
    return db.watch('''
      SELECT photo_id FROM $todosTable
      WHERE photo_id IS NOT NULL
    ''').map((results) {
      return results.map((row) => row['photo_id'] as String).toList();
    }).listen((ids) async {
      List<String> idsInQueue = await attachmentsService.getAttachmentIds();
      for (String id in ids) {
        await syncingService.reconcileId(id, idsInQueue);
      }
    });
  }
}

initializeAttachmentQueue(PowerSyncDatabase db) async {
  attachmentQueue = PhotoAttachmentQueue(db, remoteStorage);
  await attachmentQueue.init();
}
