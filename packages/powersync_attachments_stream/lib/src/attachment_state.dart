enum AttachmentState {
  pending,
  uploading,
  uploaded,
  failed,
  archived,
  synced, // New state
}

class Attachment {
  final String id;
  final AttachmentState state;
  final bool hasSynced;
  final Map<String, dynamic>? metaData;
  final String? mediaType;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  Attachment({
    required this.id,
    required this.state,
    this.hasSynced = false,
    this.metaData,
    this.mediaType,
    this.createdAt,
    this.updatedAt,
  });

  Attachment copyWith({
    AttachmentState? state,
    bool? hasSynced,
    Map<String, dynamic>? metaData,
    String? mediaType,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return Attachment(
      id: id,
      state: state ?? this.state,
      hasSynced: hasSynced ?? this.hasSynced,
      metaData: metaData ?? this.metaData,
      mediaType: mediaType ?? this.mediaType,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}