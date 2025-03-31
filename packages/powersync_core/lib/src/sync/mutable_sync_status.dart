import 'dart:async';

import 'package:collection/collection.dart';

import 'sync_status.dart';
import 'bucket_storage.dart';
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
    downloadProgress = null;
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

  void applyCheckpointStarted(
    Map<String, LocalOperationCounters> localProgress,
    Checkpoint target,
  ) {
    downloading = true;
    downloadProgress =
        InternalSyncDownloadProgress.forNewCheckpoint(localProgress, target);
  }

  void applyUploadError(Object error) {
    uploading = false;
    uploadError = error;
  }

  void applyBatchReceived(SyncDataBatch batch) {
    downloading = true;
    if (downloadProgress case final previousProgress?) {
      downloadProgress = previousProgress.incrementDownloaded(batch);
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
      hasSynced: null, // Stream client is not supposed to set this value.
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
