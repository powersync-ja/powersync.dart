import 'dart:async';

import 'package:collection/collection.dart';

import '../sync_status.dart';
import 'protocol.dart';

final class MutableSyncStatus {
  bool connected = false;
  bool connecting = false;
  bool downloading = false;
  bool uploading = false;

  InternalSyncDownloadProgress? downloadProgress;
  List<SyncPriorityStatus> priorityStatusEntries = const [];

  DateTime? lastSyncedAt;

  Object? uploadError;
  Object? downloadError;

  void setConnectingIfNotConnected() {
    if (!connected) {
      connecting = true;
    }
  }

  void setConnected() {
    connected = true;
    connecting = false;
  }

  void applyDownloadError(Object error) {
    connected = false;
    connecting = false;
    downloading = false;
    downloadProgress = null;
    downloadError = error;
  }

  void applyCheckpointReached(Checkpoint applied) {
    downloading = false;
    downloadError = null;
    final now = lastSyncedAt = DateTime.now();
    priorityStatusEntries = [
      if (applied.checksums.isNotEmpty)
        (
          hasSynced: true,
          lastSyncedAt: now,
          priority: maxBy(
            applied.checksums.map((cs) => BucketPriority(cs.priority)),
            (priority) => priority,
            compare: BucketPriority.comparator,
          )!,
        )
    ];
  }

  void applyCheckpointStarted(Checkpoint target) {
    downloading = true;
    // TODO: Include pending ops from interrupted download, if any...
    downloadProgress = InternalSyncDownloadProgress.fromZero(target);
  }

  void applyUploadError(Object error) {
    uploading = false;
    uploadError = error;
  }

  void applyBatchReceived(
      Map<String, BucketDescription?> currentBuckets, SyncDataBatch batch) {
    downloading = true;
    if (downloadProgress case final previousProgress?) {
      downloadProgress = previousProgress.incrementDownloaded([
        for (final bucket in batch.buckets)
          if (currentBuckets[bucket.bucket] case final knownBucket?)
            (BucketPriority(knownBucket.priority), bucket.data.length),
      ]);
    }
  }

  SyncStatus immutableSnapsot() {
    return SyncStatus(
      connected: connected,
      connecting: connecting,
      downloading: downloading,
      uploading: uploading,
      downloadProgress: downloadProgress?.asSyncDownloadProgress,
      priorityStatusEntries: UnmodifiableListView(priorityStatusEntries),
      lastSyncedAt: lastSyncedAt,
      hasSynced: lastSyncedAt != null,
      uploadError: uploadError,
      downloadError: downloadError,
    );
  }
}

final class SyncStatusStateStream {
  final MutableSyncStatus status = MutableSyncStatus();
  SyncStatus _lastPublishedStatus = const SyncStatus();

  final StreamController<SyncStatus> _statusStreamController =
      StreamController<SyncStatus>.broadcast();

  Stream<SyncStatus> get statusStream => _statusStreamController.stream;

  void updateStatus(void Function(MutableSyncStatus status) change) {
    change(status);

    if (_statusStreamController.isClosed) {
      return;
    }

    final current = status.immutableSnapsot();
    if (current != _lastPublishedStatus) {
      _statusStreamController.add(current);
      _lastPublishedStatus = current;
    }
  }

  void close() {
    _statusStreamController.close();
  }
}
