import 'package:powersync_core/sqlite3_common.dart' show Row;
import 'package:powersync_core/powersync_core.dart';

enum AttachmentState {
  /// The attachment is queued for download from the remote storage.
  queuedDownload,

  /// The attachment is queued for upload to the remote storage.
  queuedUpload,

  /// The attachment is queued for deletion from the remote storage.
  queuedDelete,

  /// The attachment is fully synchronized with the remote storage.
  synced,

  /// The attachment is archived and no longer actively synchronized.
  archived;

  static AttachmentState fromInt(int value) {
    if (value < 0 || value >= AttachmentState.values.length) {
      throw ArgumentError('Invalid value for AttachmentState: $value');
    }
    return AttachmentState.values[value];
  }

  int toInt() => index;
}

const defaultAttachmentsQueueTableName = 'attachments_queue';

class Attachment {
  final String id;
  final int timestamp;
  final String filename;
  final AttachmentState state;
  final String? localUri;
  final String? mediaType;
  final int? size;
  final bool hasSynced;
  final String? metaData;

  const Attachment({
    required this.id,
    this.timestamp = 0,
    required this.filename,
    this.state = AttachmentState.queuedDownload,
    this.localUri,
    this.mediaType,
    this.size,
    this.hasSynced = false,
    this.metaData,
  });

  factory Attachment.fromRow(Row row) {
    return Attachment(
      id: row['id'] as String,
      timestamp: row['timestamp'] as int? ?? 0,
      filename: row['filename'] as String,
      localUri: row['local_uri'] as String?,
      mediaType: row['media_type'] as String?,
      size: row['size'] as int?,
      state: AttachmentState.fromInt(row['state'] as int),
      hasSynced: (row['has_synced'] as int? ?? 0) > 0,
      metaData: row['meta_data']?.toString(),
    );
  }

  /// Returns a copy of this attachment with the given fields replaced.
  Attachment copyWith({
    String? id,
    int? timestamp,
    String? filename,
    AttachmentState? state,
    String? localUri,
    String? mediaType,
    int? size,
    bool? hasSynced,
    String? metaData,
  }) {
    return Attachment(
      id: id ?? this.id,
      timestamp: timestamp ?? this.timestamp,
      filename: filename ?? this.filename,
      state: state ?? this.state,
      localUri: localUri ?? this.localUri,
      mediaType: mediaType ?? this.mediaType,
      size: size ?? this.size,
      hasSynced: hasSynced ?? this.hasSynced,
      metaData: metaData ?? this.metaData,
    );
  }
}

class AttachmentsQueueTable extends Table {
  AttachmentsQueueTable({
    String attachmentsQueueTableName = defaultAttachmentsQueueTableName,
    List<Column> additionalColumns = const [],
    List<Index> indexes = const [],
    String? viewName,
  }) : super.localOnly(
         attachmentsQueueTableName,
         [
           const Column.text('filename'),
           const Column.text('local_uri'),
           const Column.integer('timestamp'),
           const Column.integer('size'),
           const Column.text('media_type'),
           const Column.integer('state'),
           const Column.integer('has_synced'),
           const Column.text('meta_data'),
           ...additionalColumns,
         ],
         viewName: viewName,
         indexes: indexes,
       );
}
