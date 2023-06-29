class SyncStatus {
  /// true if currently connected
  final bool connected;

  /// Time that a last sync has fully completed, if any
  /// Currently this is reset to null after a restart
  final DateTime? lastSyncedAt;

  const SyncStatus({required this.connected, required this.lastSyncedAt});

  @override
  bool operator ==(Object other) {
    return (other is SyncStatus &&
        other.connected == connected &&
        other.lastSyncedAt == lastSyncedAt);
  }

  @override
  int get hashCode {
    return Object.hash(connected, lastSyncedAt);
  }

  @override
  String toString() {
    return "SyncStatus<connected: $connected lastSyncedAt: $lastSyncedAt>";
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
