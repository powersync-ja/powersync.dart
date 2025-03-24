import 'dart:math';

import 'package:collection/collection.dart';
import 'package:meta/meta.dart';

import 'sync/protocol.dart';

final class SyncStatus {
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

  /// A realtime progress report on how many operations have been downloaded and
  /// how many are necessary in total to complete the next sync iteration.
  ///
  /// This field is only set when [downloading] is also true.
  final SyncDownloadProgress? downloadProgress;

  /// true if uploading changes
  final bool uploading;

  /// Time that a last sync has fully completed, if any.
  ///
  /// This is null while loading the database.
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

  final List<SyncPriorityStatus> priorityStatusEntries;

  const SyncStatus({
    this.connected = false,
    this.connecting = false,
    this.lastSyncedAt,
    this.hasSynced,
    this.downloadProgress,
    this.downloading = false,
    this.uploading = false,
    this.downloadError,
    this.uploadError,
    this.priorityStatusEntries = const [],
  });

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
        other.hasSynced == hasSynced &&
        _statusEquality.equals(
            other.priorityStatusEntries, priorityStatusEntries));
  }

  @Deprecated('Should not be used in user code')
  SyncStatus copyWith({
    bool? connected,
    bool? downloading,
    bool? uploading,
    bool? connecting,
    Object? uploadError,
    Object? downloadError,
    DateTime? lastSyncedAt,
    bool? hasSynced,
    List<SyncPriorityStatus>? priorityStatusEntries,
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
      priorityStatusEntries:
          priorityStatusEntries ?? this.priorityStatusEntries,
    );
  }

  /// Get the current [downloadError] or [uploadError].
  Object? get anyError {
    return downloadError ?? uploadError;
  }

  /// Returns information for [lastSyncedAt] and [hasSynced] information at a
  /// partial sync priority, or `null` if the status for that priority is
  /// unknown.
  ///
  /// The information returned may be more generic than requested. For instance,
  /// a fully-completed sync cycle (as expressed by [lastSyncedAt]) necessarily
  /// includes all buckets across all priorities. So, if no further partial
  /// checkpoints have been received since that complete sync,
  /// [statusForPriority] may return information for that complete sync.
  /// Similarly, requesting the sync status for priority `1` may return
  /// information extracted from the lower priority `2` since each partial sync
  /// in priority `2` necessarily includes a consistent view over data in
  /// priority `1`.
  SyncPriorityStatus statusForPriority(BucketPriority priority) {
    assert(priorityStatusEntries.isSortedByCompare(
        (e) => e.priority, BucketPriority.comparator));

    for (final known in priorityStatusEntries) {
      // Lower-priority buckets are synchronized after higher-priority buckets,
      // and since priorityStatusEntries is sorted we look for the first entry
      // that doesn't have a higher priority.
      if (known.priority <= priority) {
        return known;
      }
    }

    // If we have a complete sync, that necessarily includes all priorities.
    return (
      priority: priority,
      hasSynced: hasSynced,
      lastSyncedAt: lastSyncedAt
    );
  }

  @override
  int get hashCode {
    return Object.hash(
        connected,
        downloading,
        uploading,
        connecting,
        uploadError,
        downloadError,
        lastSyncedAt,
        _statusEquality.hash(priorityStatusEntries));
  }

  @override
  String toString() {
    return "SyncStatus<connected: $connected connecting: $connecting downloading: $downloading uploading: $uploading lastSyncedAt: $lastSyncedAt, hasSynced: $hasSynced, error: $anyError>";
  }

  // This should be a ListEquality<SyncPriorityStatus>, but that appears to
  // cause weird type errors with DDC (but only after hot reloads?!)
  static const _statusEquality = ListEquality<Object?>();
}

/// The priority of a PowerSync bucket.
extension type const BucketPriority._(int priorityNumber) {
  static const _highest = 0;

  factory BucketPriority(int i) {
    assert(i >= _highest);
    return BucketPriority._(i);
  }

  bool operator >(BucketPriority other) => comparator(this, other) > 0;
  bool operator >=(BucketPriority other) => comparator(this, other) >= 0;
  bool operator <(BucketPriority other) => comparator(this, other) < 0;
  bool operator <=(BucketPriority other) => comparator(this, other) <= 0;

  /// A [Comparator] instance suitable for comparing [BucketPriority] values.
  static int comparator(BucketPriority a, BucketPriority b) =>
      -a.priorityNumber.compareTo(b.priorityNumber);
}

/// Partial information about the synchronization status for buckets within a
/// priority.
typedef SyncPriorityStatus = ({
  BucketPriority priority,
  DateTime? lastSyncedAt,
  bool? hasSynced,
});

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

@internal
final class InternalSyncDownloadProgress {
  final Map<BucketPriority, int> downloaded;
  final Map<BucketPriority, int> target;

  final int _totalDownloaded;
  final int _totalTarget;

  InternalSyncDownloadProgress(this.downloaded, this.target)
      : _totalDownloaded = target.values.sum,
        _totalTarget = target.values.sum;

  factory InternalSyncDownloadProgress.fromZero(Checkpoint target) {
    final targetOps = target.checksums.groupFoldBy<BucketPriority, int>(
      (cs) => BucketPriority(cs.priority),
      (prev, cs) => (prev ?? 0) + (cs.count ?? 0),
    );
    final downloaded = targetOps.map((k, v) => MapEntry(k, 0));

    return InternalSyncDownloadProgress(downloaded, targetOps);
  }

  static InternalSyncDownloadProgress ofPublic(SyncDownloadProgress public) {
    return public._internal;
  }

  static int sumInPriority(
      Map<BucketPriority, int> counters, BucketPriority priority) {
    return counters.entries
        .where((e) => e.key >= priority)
        .map((e) => e.value)
        .sum;
  }

  InternalSyncDownloadProgress incrementDownloaded(
      List<(BucketPriority, int)> opsInPriority) {
    var downloadedOps = {...downloaded};

    for (final (priority, addedOps) in opsInPriority) {
      assert(downloaded.containsKey(priority));
      assert(target.containsKey(priority));

      downloadedOps[priority] =
          max(downloadedOps[priority]! + addedOps, target[priority]!);
    }

    return InternalSyncDownloadProgress(downloadedOps, target);
  }

  SyncDownloadProgress get asSyncDownloadProgress =>
      SyncDownloadProgress._(this);

  @override
  int get hashCode => Object.hash(
        _mapEquality.hash(downloaded),
        _mapEquality.hash(target),
      );

  @override
  bool operator ==(Object other) {
    return other is InternalSyncDownloadProgress &&
        // _totalDownloaded and _totalTarget are derived values, but comparing
        // them first helps find a difference faster.
        _totalDownloaded == other._totalDownloaded &&
        _totalTarget == other._totalTarget &&
        _mapEquality.equals(downloaded, other.downloaded) &&
        _mapEquality.equals(target, other.target);
  }

  static const _mapEquality = MapEquality<Object?, Object?>();
}

typedef ProgressWithOperations = ({
  int total,
  int completed,
  double fraction,
});

/// Provides realtime progress about how PowerSync is downloading rows.
///
/// The reported progress always reflects the status towards the end of a
/// sync iteration (after which a consistent snapshot of all buckets is
/// available locally). Note that [downloaded] starts at `0` every time an
/// iteration begins.
/// This has an effect when iterations are interrupted. Consider this flow
/// as an example:
///
///   1. The client comes online for the first time and has to synchronize a
///      large amount of rows (say 100k). Here, [downloaded] starts at `0` and
///      [total] would be the `100,000` rows.
///   2. The client makes some progress, so that [downloaded] is perhaps
///      `60,000`.
///   3. The client briefly looses connectivity.
///   4. Back online, a new sync iteration starts. This means that [downloaded]
///      is reset to `0`. However, since half of the target has already been
///      downloaded in the earlier iteration, [total] is now set to `40,000` to
///      reflect the remaining rows to download in the new iteration.
extension type SyncDownloadProgress._(InternalSyncDownloadProgress _internal) {
  /// The amount of operations that have been downloaded in the current sync
  /// iteration.
  ///
  /// This number always starts at zero as [SyncStatus.downloading] changes
  /// from `false` to `true`.
  int get downloaded => _internal._totalDownloaded;

  /// The total amount of operations expected for this sync operation.
  int get total => _internal._totalTarget;

  /// The fraction of [total] operations that have already been [downloaded], as
  /// a number between 0 and 1.
  double get progress => _internal._totalDownloaded / _internal._totalTarget;

  ProgressWithOperations get untilCompletion => (
        total: total,
        completed: downloaded,
        fraction: progress,
      );

  ProgressWithOperations untilPriority(BucketPriority priority) {
    final downloaded = downloadedFor(priority);
    final total = totalFor(priority);
    final progress = total == 0 ? 0.0 : downloaded / total;

    return (
      total: totalFor(priority),
      completed: downloaded,
      fraction: progress,
    );
  }

  /// Returns how many operations have been downloaded for buckets in
  /// [priority].
  ///
  /// Under the consistency guarantees offered by PowerSync, this will also
  /// include operations from higher-priority buckets.
  int downloadedFor(BucketPriority priority) {
    return InternalSyncDownloadProgress.sumInPriority(
        _internal.downloaded, priority);
  }

  /// Returns how many operations in total need to be downloaded before the
  /// client has reached a consistent states for buckets with the given
  /// [priority].
  ///
  /// Under the consistency guarantees offered by PowerSync, this will also
  /// include operations from higher-priority buckets.
  int totalFor(BucketPriority priority) {
    return InternalSyncDownloadProgress.sumInPriority(
        _internal.target, priority);
  }

  /// The progress towards syncing the given [priority].
  ///
  /// Returns the fraction of [downloadedFor] to [totalFor], as a number between
  /// 0 and 1.
  double progressFor(BucketPriority priority) {
    final downloaded = downloadedFor(priority);
    final total = totalFor(priority);

    if (total == 0) {
      return 0;
    }

    return downloaded / total;
  }
}
