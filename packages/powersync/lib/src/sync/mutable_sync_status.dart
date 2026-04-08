import 'dart:async';

import 'package:collection/collection.dart';

import 'instruction.dart';
import 'stream.dart';
import 'sync_status.dart';

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

  void applyUploadError(Object error) {
    uploading = false;
    uploadError = error;
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
