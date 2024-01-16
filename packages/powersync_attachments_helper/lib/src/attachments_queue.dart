import 'dart:async';

import './attachments_queue_table.dart';
import './attachments_service.dart';
import './local_storage_adapter.dart';
import './remote_storage_adapter.dart';
import './syncing_service.dart';
import 'package:logging/logging.dart';
import 'package:powersync/powersync.dart';

/// Logger for the attachment queue
final log = Logger('AttachmentQueue');

/// Abstract class used to implement the attachment queue
/// Requires a PowerSyncDatabase, an implementation of
/// AbstractRemoteStorageAdapter and an attachment directory name which will
/// determine which folder attachments are stored into.
abstract class AbstractAttachmentQueue {
  PowerSyncDatabase db;
  AbstractRemoteStorageAdapter remoteStorage;
  String attachmentDirectoryName;
  late AttachmentsService attachmentsService;
  late SyncingService syncingService;
  final LocalStorageAdapter localStorage = LocalStorageAdapter();

  AbstractAttachmentQueue(
      {required this.db,
      required this.remoteStorage,
      this.attachmentDirectoryName = 'attachments',
      performInitialSync = true}) {
    attachmentsService =
        AttachmentsService(db, localStorage, attachmentDirectoryName);
    syncingService = SyncingService(
        db, remoteStorage, localStorage, attachmentsService, getLocalUri);
  }

  /// Create watcher to get list of ID's from a table to be used for syncing in the attachment queue.
  /// Set the file extension if you are using a different file type
  StreamSubscription<void> watchIds({String fileExtension = 'jpg'});

  /// Create a function to save photos using the attachment queue
  Future<Attachment> savePhoto(String photoId, int size);

  /// Create a function to delete photos using the attachment queue
  Future<Attachment> deletePhoto(String photoId);

  /// Initialize the attachment queue by
  /// 1. Creating attachments directory
  /// 2. Adding watches for uploads, downloads, and deletes
  /// 3. Adding trigger to run uploads, downloads, and deletes when device is online after being offline
  init() async {
    // Ensure the directory where attachments are downloaded, exists
    await localStorage.makeDir(await getStorageDirectory());

    watchIds();
    syncingService.watchUploads();
    syncingService.watchDownloads();
    syncingService.watchDeletes();

    db.statusStream.listen((status) {
      if (db.currentStatus.connected) {
        _trigger();
      }
    });
  }

  _trigger() async {
    await syncingService.runDownloads();
    await syncingService.runDeletes();
    await syncingService.runUploads();
  }

  /// Returns the local file path for the given filename, used to store in the database.
  /// Example: filename: "attachment-1.jpg" returns "attachments/attachment-1.jpg"
  String getLocalFilePathSuffix(String filename) {
    return '$attachmentDirectoryName/$filename';
  }

  /// Returns the directory where attachments are stored on the device, used to make dir
  /// Example: "/var/mobile/Containers/Data/Application/.../Library/attachments/"
  Future<String> getStorageDirectory() async {
    String userStorageDirectory = await localStorage.getUserStorageDirectory();
    return '$userStorageDirectory/$attachmentDirectoryName';
  }

  /// Return users storage directory with the attachmentPath use to load the file.
  /// Example: filePath: "attachments/attachment-1.jpg" returns "/var/mobile/Containers/Data/Application/.../Library/attachments/attachment-1.jpg"
  Future<String> getLocalUri(String filePath) async {
    String storageDirectory = await getStorageDirectory();
    return '$storageDirectory/$filePath';
  }
}
