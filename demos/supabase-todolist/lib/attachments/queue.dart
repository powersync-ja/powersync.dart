import 'dart:async';

import 'package:logging/logging.dart';
import 'package:powersync/powersync.dart';
import 'package:powersync_core/attachments/attachments.dart';

import 'package:powersync_flutter_demo/attachments/remote_storage_adapter.dart';

import 'local_storage_unsupported.dart'
    if (dart.library.io) 'local_storage_native.dart';

late AttachmentQueue attachmentQueue;
final remoteStorage = SupabaseStorageAdapter();
final logger = Logger('AttachmentQueue');

Future<void> initializeAttachmentQueue(PowerSyncDatabase db) async {
  attachmentQueue = AttachmentQueue(
    db: db,
    remoteStorage: remoteStorage,
    logger: logger,
    localStorage: await localAttachmentStorage(),
    watchAttachments: () => db.watch('''
      SELECT photo_id as id FROM todos WHERE photo_id IS NOT NULL
    ''').map(
      (results) => [
        for (final row in results)
          WatchedAttachmentItem(
            id: row['id'] as String,
            fileExtension: 'jpg',
          )
      ],
    ),
  );

  await attachmentQueue.startSync();
}

Future<Attachment> savePhotoAttachment(
    Stream<List<int>> photoData, String todoId,
    {String mediaType = 'image/jpeg'}) async {
  // Save the file using the AttachmentQueue API
  return await attachmentQueue.saveFile(
    data: photoData,
    mediaType: mediaType,
    fileExtension: 'jpg',
    metaData: 'Photo attachment for todo: $todoId',
    updateHook: (context, attachment) async {
      // Update the todo item to reference this attachment
      await context.execute(
        'UPDATE todos SET photo_id = ? WHERE id = ?',
        [attachment.id, todoId],
      );
    },
  );
}
