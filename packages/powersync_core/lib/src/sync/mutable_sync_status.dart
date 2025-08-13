import 'dart:async';

import 'package:collection/collection.dart';

import 'instruction.dart';
import 'stream.dart';
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
  List<CoreActiveStreamSubscription>? streams;

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
            applied.checksums.map((cs) => StreamPriority(cs.priority)),
            (priority) => priority,
            compare: StreamPriority.comparator,
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

  void applyFromCore(CoreSyncStatus status) {
    connected = status.connected;
    connecting = status.connecting;
    downloading = status.downloading != null;
    priorityStatusEntries = status.priorityStatus;
    downloadProgress = switch (status.downloading) {
      null => null,
      final downloading => InternalSyncDownloadProgress(downloading.buckets),
    };
    lastSyncedAt = status.priorityStatus
        .firstWhereOrNull((s) => s.priority == StreamPriority.fullSyncPriority)
        ?.lastSyncedAt;
    streams = status.streams;
  }

  SyncStatus immutableSnapshot({bool setLastSynced = false}) {
    return SyncStatus(
      connected: connected,
      connecting: connecting,
      downloading: downloading,
      uploading: uploading,
      downloadProgress: downloadProgress?.asSyncDownloadProgress,
      priorityStatusEntries: UnmodifiableListView(priorityStatusEntries),
      lastSyncedAt: lastSyncedAt,
      hasSynced: setLastSynced ? lastSyncedAt != null : null,
      uploadError: uploadError,
      downloadError: downloadError,
      streamSubscriptions: streams,
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

    final current = status.immutableSnapshot();
    if (current != _lastPublishedStatus) {
      _statusStreamController.add(current);
      _lastPublishedStatus = current;
    }
  }

  void close() {
    _statusStreamController.close();
  }
}
