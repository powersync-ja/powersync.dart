import '../abstractions/attachment_context.dart';
import '../attachment.dart';
import 'package:powersync_core/powersync_core.dart';
import 'package:powersync_core/sqlite3_common.dart';
import 'package:logging/logging.dart';

class AttachmentContextImpl implements AttachmentContext {
  final PowerSyncDatabase db;
  final Logger log;
  final int maxArchivedCount;
  final String attachmentsQueueTableName;

  AttachmentContextImpl(
    this.db,
    this.log,
    this.maxArchivedCount,
    this.attachmentsQueueTableName,
  );

  /// Table used for storing attachments in the attachment queue.
  String get table {
    return attachmentsQueueTableName;
  }

  @override
  Future<void> deleteAttachment(String id, dynamic tx) async {
    log.info('deleteAttachment: $id');
    await tx.execute('DELETE FROM $table WHERE id = ?', [id]);
  }

  @override
  Future<void> ignoreAttachment(String id) async {
    await db.execute(
      'UPDATE $table SET state = ${AttachmentState.archived.index} WHERE id = ?',
      [id],
    );
  }

  @override
  Future<Attachment?> getAttachment(String id) async {
    final row = await db.getOptional('SELECT * FROM $table WHERE id = ?', [id]);
    if (row == null) {
      return null;
    }
    return Attachment.fromRow(row);
  }

  @override
  Future<Attachment> saveAttachment(Attachment attachment) async {
    Attachment updatedRecord = attachment.copyWith(
      timestamp: DateTime.now().millisecondsSinceEpoch,
    );

    await db.execute(
      '''
      INSERT OR REPLACE INTO $table
      (id, timestamp, filename, local_uri, media_type, size, state) VALUES (?, ?, ?, ?, ?, ?, ?)
    ''',
      [
        updatedRecord.id,
        updatedRecord.timestamp,
        updatedRecord.filename,
        updatedRecord.localUri,
        updatedRecord.mediaType,
        updatedRecord.size,
        updatedRecord.state.index,
      ],
    );

    return updatedRecord;
  }

  @override
  Future<void> saveAttachments(List<Attachment> attachments) async {
    if (attachments.isEmpty) {
      log.info('No attachments to save.');
      return;
    }

    final updatedRecords = attachments.map((attachment) {
      final updated = attachment.copyWith(
        timestamp: DateTime.now().millisecondsSinceEpoch,
      );
      return [
        updated.id,
        updated.filename,
        updated.localUri,
        updated.mediaType,
        updated.size,
        updated.timestamp,
        updated.state.index,
      ];
    }).toList();

    log.info('Saving ${updatedRecords.length} attachments...');

    await db.executeBatch('''
      INSERT OR REPLACE INTO $table
      (id, filename, local_uri, media_type, size, timestamp, state) VALUES (?, ?, ?, ?, ?, ?, ?)
    ''', updatedRecords);
  }

  @override
  Future<List<String>> getAttachmentIds() async {
    ResultSet results = await db.getAll(
      'SELECT id FROM $table WHERE id IS NOT NULL',
    );

    List<String> ids = results.map((row) => row['id'] as String).toList();

    return ids;
  }

  @override
  Future<List<Attachment>> getAttachments() async {
    final results = await db.getAll('SELECT * FROM $table');
    return results.map((row) => Attachment.fromRow(row)).toList();
  }

  @override
  Future<List<Attachment>> getActiveAttachments() async {
    // Return all attachments that are not archived (i.e., state != AttachmentState.archived)
    final results = await db.getAll('SELECT * FROM $table WHERE state != ?', [
      AttachmentState.archived.index,
    ]);
    return results.map((row) => Attachment.fromRow(row)).toList();
  }

  @override
  Future<void> clearQueue() async {
    log.info('Clearing attachment queue...');
    await db.execute('DELETE FROM $table');
  }

  @override
  Future<bool> deleteArchivedAttachments(
    Future<void> Function(List<Attachment>) callback,
  ) async {
    // Find all archived attachments
    final results = await db.getAll('SELECT * FROM $table WHERE state = ?', [
      AttachmentState.archived.index,
    ]);
    final archivedAttachments = results
        .map((row) => Attachment.fromRow(row))
        .toList();

    if (archivedAttachments.isEmpty) {
      return false;
    }

    log.info('Deleting ${archivedAttachments.length} archived attachments...');
    // Call the callback with the list of archived attachments before deletion
    await callback(archivedAttachments);

    // Delete the archived attachments from the table
    final ids = archivedAttachments.map((a) => a.id).toList();
    // Use a batch delete for efficiency
    final placeholders = List.filled(ids.length, '?').join(',');
    await db.execute('DELETE FROM $table WHERE id IN ($placeholders)', ids);

    log.info('Deleted ${archivedAttachments.length} archived attachments.');
    return true;
  }

  @override
  Future<Attachment> upsertAttachment(
    Attachment attachment,
    dynamic context,
  ) async {

    await context.execute(
      '''INSERT OR REPLACE INTO 
                    $table (id, timestamp, filename, local_uri, media_type, size, state, has_synced, meta_data) 
                VALUES
                    (?, ?, ?, ?, ?, ?, ?, ?, ?)''',
      [
        attachment.id,
        attachment.timestamp,
        attachment.filename,
        attachment.localUri,
        attachment.mediaType,
        attachment.size,
        attachment.state.index,
        // attachment.state,
        attachment.hasSynced ? 1 : 0,
        attachment.metaData,
      ],
    );
    return attachment;
  }
}
