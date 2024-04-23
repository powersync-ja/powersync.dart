# PowerSync Attachments Helper for Dart/Flutter

[PowerSync Attachments Helper](https://pub.dev/packages/powersync_attachments_helper) is a package that assist in keeping files in sync with local and remote storage.

## Features

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
  Future<Attachment> saveFile(String fileId, int size) async {
    String filename = '$fileId.jpg';
    Attachment photoAttachment = Attachment(
      id: fileId,
      filename: filename,
      state: AttachmentState.queuedUpload.index,
      mediaType: 'image/jpeg',
      localUri: getLocalFilePathSuffix(filename),
      size: size,
    );

    return attachmentsService.saveAttachment(photoAttachment);
  }

  // This will create an item on the attachment queue to DELETE a file
  // in local and remote storage
  @override
  Future<Attachment> deleteFile(String fileId) async {
    String filename = '$fileId.jpg';
    Attachment photoAttachment = Attachment(
        id: fileId,
        filename: filename,
        state: AttachmentState.queuedDelete.index);

    return attachmentsService.saveAttachment(photoAttachment);
  }

  // This watcher will handle adding items to the queue based on
  // a users table element receiving a photoId
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

// Use this in your main.dart to setup and start the queue
initializeAttachmentQueue(PowerSyncDatabase db) async {
  attachmentQueue = PhotoAttachmentQueue(db, remoteStorage);
  await attachmentQueue.init();
}
```

See our [Supabase Flutter To-Do List example app](../../demos/supabase-todolist/README.md) for a concrete implementation of the above.
