import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:logging/logging.dart';
import 'package:path_provider/path_provider.dart';
import 'package:powersync/powersync.dart';
import 'package:powersync_attachments_stream/powersync_attachments_stream.dart';
import 'package:powersync_flutter_demo_new/attachments/remote_storage_adapter.dart';

late AttachmentQueue attachmentQueue;
final remoteStorage = SupabaseStorageAdapter();
final log = Logger('AttachmentQueue');

Future<bool> onDownloadError(Attachment attachment, Object exception) async {
  if (exception.toString().contains('Object not found')) {
    return false;
  }
  return true;
}

Future<void> initializeAttachmentQueue(PowerSyncDatabase db) async {
  // Use the app's document directory for local storage
  final Directory appDocDir = await getApplicationDocumentsDirectory();
  final localStorage = IOLocalStorage(appDocDir);

  log.info('directory: ${appDocDir.path}');
  log.info('localStorage: $localStorage');

  attachmentQueue = AttachmentQueue(
    db: db,
    remoteStorage: remoteStorage,
    attachmentsDirectory: '${appDocDir.path}/attachments',
    watchAttachments: () => db.watch('''
      SELECT photo_id as id FROM todos WHERE photo_id IS NOT NULL
    ''').map((results) {
      final items = results.map((row) => WatchedAttachmentItem(id: row['id'] as String, fileExtension: 'jpg')).toList();
      log.info('Watched attachment IDs: ${items.map((e) => e.id).toList()}');
      return items;
    }),
    localStorage: localStorage,
    errorHandler: null, 
  );
}

Future<Attachment> savePhotoAttachment(Stream<Uint8List> photoData, String todoId,
    {String mediaType = 'image/jpeg'}) async {
  log.info('Saving photo attachment for todo: $todoId');
  
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
  log.info('deletePhotoAttachment: $fileId');
  return await attachmentQueue.deleteFile(
    attachmentId: fileId,
    updateHook: (context, attachment) async {
      // Optionally update relationships in the same transaction
    },
  );
}
