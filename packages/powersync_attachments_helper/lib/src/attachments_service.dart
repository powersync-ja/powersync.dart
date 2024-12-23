import './attachments_queue.dart';
import './attachments_queue_table.dart';
import './local_storage_adapter.dart';
import 'package:powersync_core/powersync_core.dart';
import 'package:powersync_core/sqlite3_common.dart';

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

  /// Save the attachments to the attachment queue.
  Future<void> saveAttachments(List<Attachment> attachments) async {
    if (attachments.isEmpty) {
      return;
    }
    List<List<String>> ids = List.empty(growable: true);

    RegExp extractObjectValueRegEx = RegExp(r': (.*?)(?:,|$)');

    // This adds a timestamp to the attachments and
    // extracts the values from the attachment object
    // e.g "foo: bar, baz: qux" => ["bar", "qux"]
    // TODO: Extract value without needing to use regex
    List<List<String?>> updatedRecords = attachments
        .map((attachment) {
          ids.add([attachment.id]);
          return attachment.copyWith(
            timestamp: DateTime.now().millisecondsSinceEpoch,
          );
        })
        .toList()
        .map((attachment) {
          return extractObjectValueRegEx
              .allMatches(attachment.toString().replaceAll('}', ''))
              .map((match) => match.group(1))
              .toList();
        })
        .toList();

    await db.executeBatch('''
      INSERT OR REPLACE INTO $table
      (id, filename, local_uri, media_type, size, timestamp, state) VALUES (?, ?, ?, ?, ?, ?, ?)
    ''', updatedRecords);

    return;
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
