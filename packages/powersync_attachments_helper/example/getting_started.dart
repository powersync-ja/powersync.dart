import 'dart:async';

import 'package:powersync_attachments_helper/powersync_attachments_helper.dart';
import 'package:powersync/powersync.dart';

const schema = Schema([
  Table('users', [Column.text('name'), Column.text('photo_id')])
]);

// Assume PowerSync database is initialized elsewhere
late PowerSyncDatabase db;
// Assume remote storage is implemented elsewhere
late AbstractRemoteStorageAdapter remoteStorage;
late PhotoAttachmentQueue attachmentQueue;

class PhotoAttachmentQueue extends AbstractAttachmentQueue {
  PhotoAttachmentQueue(db, remoteStorage)
      : super(db: db, remoteStorage: remoteStorage);

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
  StreamSubscription<void> watchIds({String fileExtension = 'jpg'}) {
    return db.watch('''
      SELECT photo_id FROM users
      WHERE photo_id IS NOT NULL
    ''').map((results) {
      return results.map((row) => row['photo_id'] as String).toList();
    }).listen((ids) async {
      List<String> idsInQueue = await attachmentsService.getAttachmentIds();
      List<String> relevantIds =
          ids.where((element) => !idsInQueue.contains(element)).toList();
      syncingService.processIds(relevantIds, fileExtension);
    });
  }
}

initializeAttachmentQueue(PowerSyncDatabase db) async {
  attachmentQueue = PhotoAttachmentQueue(db, remoteStorage);
  await attachmentQueue.init();
}
