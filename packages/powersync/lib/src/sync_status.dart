class SyncStatus {
  /// true if currently connected.
  ///
  /// This means the PowerSync connection is ready to download, and
  /// [PowerSyncBackendConnector.uploadData] may be called for any local changes.
  final bool connected;

  /// true if the PowerSync connection is busy connecting.
  ///
  /// During this stage, [PowerSyncBackendConnector.uploadData] may already be called,
  /// called, and [uploading] may be true.
  final bool connecting;

  /// true if actively downloading changes.
  ///
  /// This is only true when [connected] is also true.
  final bool downloading;

  /// true if uploading changes
  final bool uploading;

  /// Time that a last sync has fully completed, if any.
  ///
  /// Currently this is reset to null after a restart.
  final DateTime? lastSyncedAt;

  /// Indicates whether there has been at least one full sync, if any.
  /// Is null when unknown, for example when state is still being loaded from the database.
  final bool? hasSynced;

  /// Error during uploading.
  ///
  /// Cleared on the next successful upload.
  final Object? uploadError;

  /// Error during downloading (including connecting).
  ///
  /// Cleared on the next successful data download.
  final Object? downloadError;

  const SyncStatus(
      {this.connected = false,
      this.connecting = false,
      this.lastSyncedAt,
      this.hasSynced,
      this.downloading = false,
      this.uploading = false,
      this.downloadError,
      this.uploadError});

  @override
  bool operator ==(Object other) {
    return (other is SyncStatus &&
        other.connected == connected &&
        other.downloading == downloading &&
        other.uploading == uploading &&
        other.connecting == connecting &&
        other.downloadError == downloadError &&
        other.uploadError == uploadError &&
        other.lastSyncedAt == lastSyncedAt &&
        other.hasSynced == hasSynced);
  }

  SyncStatus copyWith({
    bool? connected,
    bool? downloading,
    bool? uploading,
    bool? connecting,
    Object? uploadError,
    Object? downloadError,
    DateTime? lastSyncedAt,
    bool? hasSynced,
  }) {
    return SyncStatus(
      connected: connected ?? this.connected,
      downloading: downloading ?? this.downloading,
      uploading: uploading ?? this.uploading,
      connecting: connecting ?? this.connecting,
      uploadError: uploadError ?? this.uploadError,
      downloadError: downloadError ?? this.downloadError,
      lastSyncedAt: lastSyncedAt ?? this.lastSyncedAt,
      hasSynced: hasSynced ?? this.hasSynced,
    );
  }

  /// Get the current [downloadError] or [uploadError].
  Object? get anyError {
    return downloadError ?? uploadError;
  }

  @override
  int get hashCode {
    return Object.hash(connected, downloading, uploading, connecting,
        uploadError, downloadError, lastSyncedAt);
  }

  @override
  String toString() {
    return "SyncStatus<connected: $connected connecting: $connecting downloading: $downloading uploading: $uploading lastSyncedAt: $lastSyncedAt, hasSynced: $hasSynced, error: $anyError>";
  }
}

/// Stats of the local upload queue.
class UploadQueueStats {
  /// Number of records in the upload queue.
  int count;

  /// Size of the upload queue in bytes.
  int? size;

  UploadQueueStats({required this.count, this.size});

  @override
  String toString() {
    if (size == null) {
      return "UploadQueueStats<count: $count>";
    } else {
      return "UploadQueueStats<count: $count size: ${size! / 1024}kB>";
    }
  }
}
