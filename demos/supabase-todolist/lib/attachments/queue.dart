import 'dart:async';
import 'dart:io';

import 'package:logging/logging.dart';
import 'package:path_provider/path_provider.dart';
import 'package:powersync/powersync.dart';
import 'package:powersync_core/attachments_stream/attachment_queue_service.dart';
import 'package:powersync_core/attachments_stream/storage/io_local_storage.dart';
import 'package:powersync_core/attachments_stream/attachment.dart';
import 'package:powersync_flutter_demo/attachments/remote_storage_adapter.dart';

late AttachmentQueue attachmentQueue;
final remoteStorage = SupabaseStorageAdapter();
final logger = Logger('AttachmentQueue');

Future<void> initializeAttachmentQueue(PowerSyncDatabase db) async {
  // Use the app's document directory for local storage
  final Directory appDocDir = await getApplicationDocumentsDirectory();

  attachmentQueue = AttachmentQueue(
    db: db,
    remoteStorage: remoteStorage,
    logger: logger,
    localStorage: IOLocalStorage(appDocDir.path),
    watchAttachments: () => db.watch('''
      SELECT photo_id as id FROM todos WHERE photo_id IS NOT NULL
    ''').map((results) => results
        .map((row) => WatchedAttachmentItem(
              id: row['id'] as String,
              fileExtension: 'jpg',
            ))
        .toList()),
  );

  await attachmentQueue.startSync();
}

Future<Attachment> savePhotoAttachment(List<int> photoData, String todoId,
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

Future<Attachment> deletePhotoAttachment(String fileId) async {
  return await attachmentQueue.deleteFile(
    attachmentId: fileId,
    updateHook: (context, attachment) async {
      // Optionally update relationships in the same transaction
    },
  );
}
