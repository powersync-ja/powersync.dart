import 'package:collection/collection.dart';

import 'instruction.dart';
import 'sync_status.dart';

/// A patch that can be applied on an existing [SyncStatus] instance.
final class SyncStatusUpdate {
  /// When non-null, a changed sync status received from the core extension.
  CoreSyncStatus? core;

  /// When non-null, a changed `uploading` status indicator.
  bool? uploading;

  /// When non-null, a changed download error.
  ///
  /// To clear the download error, this is set to [resetSentinel].
  Object? downloadError;

  /// When non-null, a changed upload error.
  ///
  /// To clear the upload error, this is set to [resetSentinel].
  Object? uploadError;

  SyncStatusUpdate({
    this.core,
    this.uploading,
    this.downloadError,
    this.uploadError,
  });

  @override
  String toString() {
    final namedEntries = [
      if (core case final core?) ('core', core),
      if (uploading case final uploading?) ('uploading', uploading),
      if (downloadError != null)
        ('downloadError', _applyError(null, downloadError)),
      if (uploadError != null) ('uploadError', _applyError(null, uploadError)),
    ];

    return 'SyncStatusUpdate(${namedEntries.map((pair) => '${pair.$1}: ${pair.$2}').join(', ')})';
  }

  SyncStatus applyTo(SyncStatus status) {
    final core = this.core;

    return SyncStatus(
      connected: core?.connected ?? status.connected,
      connecting: core?.connecting ?? status.connecting,
      downloading: core == null ? status.downloading : core.downloading != null,
      uploading: uploading ?? status.uploading,
      downloadProgress: core == null
          ? status.downloadProgress
          : switch (core.downloading) {
              null => null,
              final downloading => InternalSyncDownloadProgress(
                downloading.buckets,
              ).asSyncDownloadProgress,
            },
      priorityStatusEntries: core == null
          ? status.priorityStatusEntries
          : UnmodifiableListView(core.priorityStatus),
      lastSyncedAt: core == null
          ? status.lastSyncedAt
          : core.priorityStatus
                .firstWhereOrNull(
                  (s) => s.priority == StreamPriority.fullSyncPriority,
                )
                ?.lastSyncedAt,
      uploadError: _applyError(status.uploadError, uploadError),
      downloadError: _applyError(status.downloadError, downloadError),
      streamSubscriptions: core == null
          ? status.internalSubscriptions
          : core.streams,
      lastAppliedCheckpoint: core == null
          ? status.lastAppliedCheckpoint
          : core.lastAppliedCheckpointRequestId,
    );
  }

  static const resetSentinel = #reset;

  static Object? _applyError(Object? previousError, Object? newError) {
    if (resetSentinel == newError) {
      return null;
    } else {
      return newError ?? previousError;
    }
  }
}
