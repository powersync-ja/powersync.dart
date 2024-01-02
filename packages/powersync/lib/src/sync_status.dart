class SyncStatus {
  /// true if currently connected
  final bool connected;

  /// true if currently connected
  final bool connecting;

  /// true if downloading changes
  final bool downloading;

  /// true if uploading changes
  final bool uploading;

  /// Time that a last sync has fully completed, if any
  /// Currently this is reset to null after a restart
  final DateTime? lastSyncedAt;

  /// Error during uploading.
  /// Cleared on the next successful upload.
  final Object? uploadError;

  /// Error during downloading (including connecting).
  /// Cleared on the next successful data download.
  final Object? downloadError;

  const SyncStatus(
      {this.connected = false,
      this.connecting = false,
      this.lastSyncedAt,
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
        other.lastSyncedAt == lastSyncedAt);
  }

  // Get the current [downloadError] or [uploadError] as an Exception;
  Exception? get exception {
    if (downloadError is Exception) {
      return downloadError as Exception;
    } else if (downloadError != null) {
      return Exception('Download error: $downloadError');
    } else if (uploadError is Exception) {
      return uploadError as Exception;
    } else if (uploadError != null) {
      return Exception('Upload error: $uploadError');
    } else {
      return null;
    }
  }

  @override
  int get hashCode {
    return Object.hash(connected, downloading, uploading, connecting,
        uploadError, downloadError, lastSyncedAt);
  }

  @override
  String toString() {
    return "SyncStatus<connected: $connected downloading: $downloading uploading: $uploading lastSyncedAt: $lastSyncedAt error: $exception>";
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
