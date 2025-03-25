import 'dart:async';

import 'package:powersync_attachments_helper/powersync_attachments_helper.dart';
import 'package:riverpod/riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:supabase_todolist_drift/app_config.dart';
import 'package:supabase_todolist_drift/attachments/remote_storage_adapter.dart';

import 'package:supabase_todolist_drift/models/schema.dart';
import 'package:supabase_todolist_drift/powersync.dart' hide log;

part 'queue.g.dart';

@Riverpod(keepAlive: true)
Future<PhotoAttachmentQueue> attachmentQueue(Ref ref) async {
  final db = await ref.read(powerSyncInstanceProvider.future);
  final queue = PhotoAttachmentQueue(db, remoteStorage);
  await queue.init();
  return queue;
}

final remoteStorage = SupabaseStorageAdapter();

/// Function to handle errors when downloading attachments
/// Return false if you want to archive the attachment
Future<bool> onDownloadError(Attachment attachment, Object exception) async {
  if (exception.toString().contains('Object not found')) {
    return false;
  }
  return true;
}

class PhotoAttachmentQueue extends AbstractAttachmentQueue {
  PhotoAttachmentQueue(db, remoteStorage)
      : super(
            db: db,
            remoteStorage: remoteStorage,
            onDownloadError: onDownloadError);

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
  Future<Attachment> saveFile(String fileId, int size,
      {mediaType = 'image/jpeg'}) async {
    String filename = '$fileId.jpg';

    Attachment photoAttachment = Attachment(
      id: fileId,
      filename: filename,
      state: AttachmentState.queuedUpload.index,
      mediaType: mediaType,
      localUri: getLocalFilePathSuffix(filename),
      size: size,
    );

    return attachmentsService.saveAttachment(photoAttachment);
  }

  @override
  Future<Attachment> deleteFile(String fileId) async {
    String filename = '$fileId.jpg';

    Attachment photoAttachment = Attachment(
        id: fileId,
        filename: filename,
        state: AttachmentState.queuedDelete.index);

    return attachmentsService.saveAttachment(photoAttachment);
  }

  @override
  StreamSubscription<void> watchIds({String fileExtension = 'jpg'}) {
    log.info('Watching photos in $todosTable...');
    return db.watch('''
      SELECT photo_id FROM $todosTable
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
