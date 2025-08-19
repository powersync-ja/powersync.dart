import 'package:powersync_core/powersync_core.dart';
import 'package:powersync_core/sqlite3_common.dart';
import 'package:logging/logging.dart';
import 'package:sqlite_async/sqlite_async.dart';
import 'package:meta/meta.dart';

import '../attachment.dart';

@internal
final class AttachmentContext {
  final PowerSyncDatabase db;
  final Logger log;
  final int maxArchivedCount;
  final String attachmentsQueueTableName;

  AttachmentContext(
    this.db,
    this.log,
    this.maxArchivedCount,
    this.attachmentsQueueTableName,
  );

  /// Table used for storing attachments in the attachment queue.
  String get table {
    return attachmentsQueueTableName;
  }

  Future<void> deleteAttachment(String id) async {
    log.info('deleteAttachment: $id');
    await db.writeTransaction((tx) async {
      await tx.execute('DELETE FROM $table WHERE id = ?', [id]);
    });
  }

  Future<void> ignoreAttachment(String id) async {
    await db.execute(
      'UPDATE $table SET state = ${AttachmentState.archived.index} WHERE id = ?',
      [id],
    );
  }

  Future<Attachment?> getAttachment(String id) async {
    final row = await db.getOptional('SELECT * FROM $table WHERE id = ?', [id]);
    if (row == null) {
      return null;
    }
    return Attachment.fromRow(row);
  }

  Future<Attachment> saveAttachment(Attachment attachment) async {
    return await db.writeLock((ctx) async {
      return await upsertAttachment(attachment, ctx);
    });
  }

  Future<void> saveAttachments(List<Attachment> attachments) async {
    if (attachments.isEmpty) {
      log.info('No attachments to save.');
      return;
    }
    await db.writeTransaction((tx) async {
      for (final attachment in attachments) {
        await upsertAttachment(attachment, tx);
      }
    });
  }

  Future<List<String>> getAttachmentIds() async {
    ResultSet results = await db.getAll(
      'SELECT id FROM $table WHERE id IS NOT NULL',
    );

    List<String> ids = results.map((row) => row['id'] as String).toList();

    return ids;
  }

  Future<List<Attachment>> getAttachments() async {
    final results = await db.getAll('SELECT * FROM $table');
    return results.map((row) => Attachment.fromRow(row)).toList();
  }

  Future<List<Attachment>> getActiveAttachments() async {
    // Return all attachments that are not archived (i.e., state != AttachmentState.archived)
    final results = await db.getAll('SELECT * FROM $table WHERE state != ?', [
      AttachmentState.archived.index,
    ]);
    return results.map((row) => Attachment.fromRow(row)).toList();
  }

  Future<void> clearQueue() async {
    log.info('Clearing attachment queue...');
    await db.execute('DELETE FROM $table');
  }

  Future<bool> deleteArchivedAttachments(
    Future<void> Function(List<Attachment>) callback,
  ) async {
    // Only delete archived attachments exceeding the maxArchivedCount, ordered by timestamp DESC
    const limit = 1000;
    final results = await db.getAll(
      'SELECT * FROM $table WHERE state = ? ORDER BY timestamp DESC LIMIT ? OFFSET ?',
      [
        AttachmentState.archived.index,
        limit,
        maxArchivedCount,
      ],
    );
    final archivedAttachments =
        results.map((row) => Attachment.fromRow(row)).toList();

    if (archivedAttachments.isEmpty) {
      return false;
    }

    log.info(
        'Deleting ${archivedAttachments.length} archived attachments (exceeding maxArchivedCount=$maxArchivedCount)...');
    // Call the callback with the list of archived attachments before deletion
    await callback(archivedAttachments);

    // Delete the archived attachments from the table
    final ids = archivedAttachments.map((a) => a.id).toList();
    if (ids.isNotEmpty) {
      await db.executeBatch('DELETE FROM $table WHERE id = ?', [
        for (final id in ids) [id],
      ]);
    }

    log.info('Deleted ${archivedAttachments.length} archived attachments.');
    return archivedAttachments.length < limit;
  }

  Future<Attachment> upsertAttachment(
    Attachment attachment,
    SqliteWriteContext context,
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
        attachment.hasSynced ? 1 : 0,
        attachment.metaData,
      ],
    );

    return attachment;
  }
}
