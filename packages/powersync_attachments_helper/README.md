# PowerSync Attachments Helper SDK for Dart/Flutter

[PowerSync Attachments Helper](https://powersync.co) is a service and set of SDKs that keeps files in sync with local and remote storage

## SDK Features

* Handles syncing uploads, downloads and deletes between local and remote storage.

## Getting started

```dart
import 'dart:async';
import 'package:powersync_attachments_helper/powersync_attachments_helper.dart';
import 'package:powersync/powersync.dart';

// Set up schema with an id field that can be used in watchIds().
// In this case it is photo_id
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

  // This will create an item on the attachment queue to UPLOAD an image
  // to remote storage
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

  // This will create an item on the attachment queue to DELETE an image
  // in local and remote storage
  @override
  Future<Attachment> deletePhoto(String photoId) async {
    String filename = '$photoId.jpg';
    Attachment photoAttachment = Attachment(
        id: photoId,
        filename: filename,
        state: AttachmentState.queuedDelete.index);

    return attachmentsService.saveAttachment(photoAttachment);
  }

  // This watcher will handle adding items to the queue based on
  // a users table element receiving a photoId
  @override
  StreamSubscription<void> watchIds() {
    return db.watch('''
      SELECT photo_id FROM users
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

// Use this in your main.dart to setup and start the queue
initializeAttachmentQueue(PowerSyncDatabase db) async {
  attachmentQueue = PhotoAttachmentQueue(db, remoteStorage);
  await attachmentQueue.init();
}
```
