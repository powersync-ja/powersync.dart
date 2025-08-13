/// Defines attachment states and the Attachment model for the PowerSync attachments system.
///
/// Includes metadata, state, and utility methods for working with attachments.

import 'package:powersync_core/sqlite3_common.dart' show Row;
import 'package:powersync_core/powersync_core.dart';

import './attachment_queue_service.dart';

/// Represents the state of an attachment.
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

  /// Constructs an [AttachmentState] from the corresponding integer value.
  ///
  /// Throws [ArgumentError] if the value does not match any [AttachmentState].
  static AttachmentState fromInt(int value) {
    if (value < 0 || value >= AttachmentState.values.length) {
      throw ArgumentError('Invalid value for AttachmentState: $value');
    }
    return AttachmentState.values[value];
  }

  /// Returns the ordinal value of this [AttachmentState].
  int toInt() => index;
}

const defaultAttachmentsQueueTableName = AttachmentQueue.defaultTableName;

/// Represents an attachment with metadata and state information.
///
/// {@category Attachments}
///
/// Properties:
/// - [id]: Unique identifier for the attachment.
/// - [timestamp]: Timestamp of the last record update.
/// - [filename]: Name of the attachment file, e.g., `[id].jpg`.
/// - [state]: Current state of the attachment, represented as an ordinal of [AttachmentState].
/// - [localUri]: Local URI pointing to the attachment file, if available.
/// - [mediaType]: Media type of the attachment, typically represented as a MIME type.
/// - [size]: Size of the attachment in bytes, if available.
/// - [hasSynced]: Indicates whether the attachment has been synced locally before.
/// - [metaData]: Additional metadata associated with the attachment.
class Attachment {
  /// Unique identifier for the attachment.
  final String id;
  /// Timestamp of the last record update.
  final int timestamp;
  /// Name of the attachment file, e.g., `[id].jpg`.
  final String filename;
  /// Current state of the attachment, represented as an ordinal of [AttachmentState].
  final AttachmentState state;
  /// Local URI pointing to the attachment file, if available.
  final String? localUri;
  /// Media type of the attachment, typically represented as a MIME type.
  final String? mediaType;
  /// Size of the attachment in bytes, if available.
  final int? size;
  /// Indicates whether the attachment has been synced locally before.
  final bool hasSynced;
  /// Additional metadata associated with the attachment.
  final String? metaData;

  /// Creates an [Attachment] instance.
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

  /// Creates an [Attachment] instance from a database row.
  ///
  /// [row]: The [Row] containing attachment data.
  /// Returns an [Attachment] instance populated with data from the row.
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

/// Table definition for the attachments queue.
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
