import './attachments_queue.dart';
import './attachments_queue_table.dart';
import './local_storage_adapter.dart';
import 'package:powersync/powersync.dart';
import 'package:sqlite_async/sqlite3.dart';

/// Service for interacting with the attachment queue.
class AttachmentsService {
  final PowerSyncDatabase db;
  final LocalStorageAdapter localStorage;
  final String attachmentDirectoryName;
  final String attachmentsQueueTableName;

  AttachmentsService(this.db, this.localStorage, this.attachmentDirectoryName,
      this.attachmentsQueueTableName);

  /// Table used for storing attachments in the attachment queue.
  get table {
    return attachmentsQueueTableName;
  }

  /// Delete the attachment from the attachment queue.
  Future<void> deleteAttachment(String id) async =>
      db.execute('DELETE FROM $table WHERE id = ?', [id]);

  ///Set the state of the attachment to ignore.
  Future<void> ignoreAttachment(String id) async => db.execute(
      'UPDATE $table SET state = ${AttachmentState.archived.index} WHERE id = ?',
      [id]);

  /// Get the attachment from the attachment queue using an ID.
  Future<Attachment?> getAttachment(String id) async =>
      db.getOptional('SELECT * FROM $table WHERE id = ?', [id]).then((row) {
        if (row == null) {
          return null;
        }
        return Attachment.fromRow(row);
      });

  /// Save the attachment to the attachment queue.
  Future<Attachment> saveAttachment(Attachment attachment) async {
    Attachment updatedRecord = attachment.copyWith(
      timestamp: DateTime.now().millisecondsSinceEpoch,
    );

    await db.execute('''
      INSERT OR REPLACE INTO $table
      (id, timestamp, filename, local_uri, media_type, size, state) VALUES (?, ?, ?, ?, ?, ?, ?)
    ''', [
      updatedRecord.id,
      updatedRecord.timestamp,
      updatedRecord.filename,
      updatedRecord.localUri,
      updatedRecord.mediaType,
      updatedRecord.size,
      updatedRecord.state
    ]);

    return updatedRecord;
  }

  /// Get all the ID's of attachments in the attachment queue.
  Future<List<String>> getAttachmentIds() async {
    ResultSet results =
        await db.getAll('SELECT id FROM $table WHERE id IS NOT NULL');

    List<String> ids = results.map((row) => row['id'] as String).toList();

    return ids;
  }

  /// Helper function to clear the attachment queue
  /// Currently only used for testing purposes.
  Future<void> clearQueue() async {
    log.info('Clearing attachment queue...');
    await db.execute('DELETE FROM $table');
  }
}
