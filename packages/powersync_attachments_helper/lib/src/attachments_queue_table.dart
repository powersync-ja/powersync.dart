import 'package:powersync_core/powersync_core.dart';
import 'package:powersync_core/sqlite3_common.dart' as sqlite;

const defaultAttachmentsQueueTableName = 'attachments_queue';

/// Class used to create the attachment queue table
/// The table is local only and will not be visible in the remote database
class Attachment {
  String id;
  String filename;
  String? localUri;
  int? size;
  String? mediaType;
  int? timestamp;
  int state;

  Attachment({
    required this.id,
    required this.filename,
    this.localUri,
    this.size,
    this.mediaType,
    this.timestamp,
    required this.state,
  });

  Attachment copyWith({
    String? id,
    String? filename,
    String? localUri,
    int? size,
    String? mediaType,
    int? timestamp,
    int? state,
  }) {
    return Attachment(
        id: id ?? this.id,
        filename: filename ?? this.filename,
        localUri: localUri ?? this.localUri,
        size: size ?? this.size,
        mediaType: mediaType ?? this.mediaType,
        timestamp: timestamp ?? this.timestamp,
        state: state ?? this.state);
  }

  @override
  String toString() {
    return 'Attachment{id: $id, filename: $filename, localUri: $localUri, size: $size, mediaType: $mediaType, timestamp: $timestamp, state: $state}';
  }

  factory Attachment.fromRow(sqlite.Row row) {
    return Attachment(
      id: row['id'] as String,
      filename: row['filename'] as String,
      localUri: row['local_uri'] as String?,
      size: row['size'] as int?,
      mediaType: row['media_type'] as String?,
      timestamp: row['timestamp'] as int?,
      state: row['state'] as int,
    );
  }
}

/// Different states that an attachment in the queue can be in
/// 1. Attachment to be uploaded
/// 2. Attachment to be downloaded
/// 3. Attachment to be deleted
/// 4. Attachment to be archived
enum AttachmentState { queuedUpload, queuedDownload, queuedDelete, archived }

class AttachmentsQueueTable extends Table {
  AttachmentsQueueTable(
      {String attachmentsQueueTableName = defaultAttachmentsQueueTableName,
      List<Column> additionalColumns = const [],
      List<Index> indexes = const [],
      String? viewName})
      : super.localOnly(
            attachmentsQueueTableName,
            [
              const Column.text('filename'),
              const Column.text('local_uri'),
              const Column.integer('timestamp'),
              const Column.integer('size'),
              const Column.text('media_type'),
              const Column.integer('state'),
              ...additionalColumns,
            ],
            viewName: viewName,
            indexes: indexes);
}
