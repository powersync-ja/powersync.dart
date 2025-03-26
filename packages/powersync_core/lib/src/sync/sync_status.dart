import 'package:collection/collection.dart';
import 'package:meta/meta.dart';

import 'bucket_storage.dart';
import 'protocol.dart';

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

  /// The a bucket priority lower than the lowest priority that will ever be
  /// allowed by the sync service.
  ///
  /// This can be used as a priority that tracks complete syncs instead of
  /// partial completions.
  static const _sentinel = BucketPriority._(2147483647);

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

/// Per-bucket download progress information.
@internal
typedef BucketProgress = ({
  BucketPriority priority,
  int atLast,
  int sinceLast,
  int targetCount,
});

@internal
final class InternalSyncDownloadProgress {
  final Map<String, BucketProgress> buckets;

  final int _totalDownloaded;
  final int _totalTarget;

  InternalSyncDownloadProgress(this.buckets)
      : _totalDownloaded = buckets.values.map((e) => e.sinceLast).sum,
        _totalTarget = buckets.values.map((e) => e.targetCount - e.atLast).sum;

  factory InternalSyncDownloadProgress.forNewCheckpoint(
      Map<String, LocalOperationCounters> localProgress, Checkpoint target) {
    final buckets = <String, BucketProgress>{};
    for (final bucket in target.checksums) {
      final savedProgress = localProgress[bucket.bucket];

      buckets[bucket.bucket] = (
        priority: BucketPriority._(bucket.priority),
        atLast: savedProgress?.atLast ?? 0,
        sinceLast: savedProgress?.sinceLast ?? 0,
        targetCount: bucket.count ?? 0,
      );
    }

    return InternalSyncDownloadProgress(buckets);
  }

  static InternalSyncDownloadProgress ofPublic(SyncDownloadProgress public) {
    return public._internal;
  }

  /// Sums the total target and completed operations for all buckets up until
  /// the given [priority] (inclusive).
  (int, int) targetAndCompletedCounts(BucketPriority priority) {
    return buckets.values.fold((0, 0), (prev, entry) {
      final downloaded = entry.sinceLast;
      final total = entry.targetCount - entry.atLast;
      return (prev.$1 + total, prev.$2 + downloaded);
    });
  }

  InternalSyncDownloadProgress incrementDownloaded(SyncDataBatch batch) {
    final newBucketStates = Map.of(buckets);
    for (final dataForBucket in batch.buckets) {
      final previous = newBucketStates[dataForBucket.bucket]!;
      newBucketStates[dataForBucket.bucket] = (
        priority: previous.priority,
        atLast: previous.atLast,
        sinceLast: previous.sinceLast,
        targetCount: previous.targetCount,
      );
    }

    return InternalSyncDownloadProgress(newBucketStates);
  }

  SyncDownloadProgress get asSyncDownloadProgress =>
      SyncDownloadProgress._(this);

  @override
  int get hashCode => _mapEquality.hash(buckets);

  @override
  bool operator ==(Object other) {
    return other is InternalSyncDownloadProgress &&
        // _totalDownloaded and _totalTarget are derived values, but comparing
        // them first helps find a difference faster.
        _totalDownloaded == other._totalDownloaded &&
        _totalTarget == other._totalTarget &&
        _mapEquality.equals(buckets, other.buckets);
  }

  static const _mapEquality = MapEquality<Object?, Object?>();
}

/// Information about a progressing download.
///
/// This reports the `total` amount of operations to download, how many of them
/// have alreaady been `completed` and finally a `fraction` indicating relative
/// progress (as a number between `0.0` and `1.0`)
typedef ProgressWithOperations = ({
  int total,
  int completed,
  double fraction,
});

/// Provides realtime progress about how PowerSync is downloading rows.
///
/// The reported progress always reflects the status towards the end of a
/// sync iteration (after which a consistent snapshot of all buckets is
/// available locally).
///
/// In rare cases (in particular, when a [compacting] operation takes place
/// between syncs), it's possible for the returned numbers to be slightly
/// inaccurate. For this reason, [SyncDownloadProgress] should be seen as an
/// approximation of progress. The information returned is good enough to build
/// progress bars, but not exact enough to track individual download counts.
///
/// Also note that data is downloaded in bulk, which means that individual
/// counters are unlikely to be updated one-by-one.
///
/// [compacting]: https://docs.powersync.com/usage/lifecycle-maintenance/compacting-buckets
extension type SyncDownloadProgress._(InternalSyncDownloadProgress _internal) {
  /// Returns download progress towards a complete checkpoint being received.
  ///
  /// The returned [ProgressWithOperations] tracks the target amount of
  /// operations that need to be downloaded in total and how many of them have
  /// already been received.
  ProgressWithOperations get untilCompletion =>
      untilPriority(BucketPriority._sentinel);

  /// Returns download progress towards all data up until the specified
  /// [priority] being received.
  ///
  /// The returned [ProgressWithOperations] tracks the target amount of
  /// operations that need to be downloaded in total and how many of them have
  /// already been received.
  ProgressWithOperations untilPriority(BucketPriority priority) {
    final (total, downloaded) = _internal.targetAndCompletedCounts(priority);
    final progress = total == 0 ? 0.0 : downloaded / total;

    return (total: total, completed: downloaded, fraction: progress);
  }
}
