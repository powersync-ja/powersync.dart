import 'dart:math';

import 'package:collection/collection.dart';
import 'package:meta/meta.dart';
import '../database/powersync_database.dart';

import 'bucket_storage.dart';
import 'protocol.dart';
import 'stream.dart';

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

  final List<CoreActiveStreamSubscription>? _internalSubscriptions;

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
    List<CoreActiveStreamSubscription>? streamSubscriptions,
  }) : _internalSubscriptions = streamSubscriptions;

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
        _listEquality.equals(
            other.priorityStatusEntries, priorityStatusEntries) &&
        _listEquality.equals(
            other._internalSubscriptions, _internalSubscriptions) &&
        other.downloadProgress == downloadProgress);
  }

  // Deprecated because it can't set fields back to null
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

  /// All sync streams currently being tracked in this subscription.
  ///
  /// This returns null when the sync stream is currently being opened and we
  /// don't have reliable information about all included streams yet (in that
  /// state, [PowerSyncDatabase.subscribedStreams] can still be used to
  /// resolve known subscriptions locally).
  Iterable<SyncStreamStatus>? get activeSubscriptions {
    return _internalSubscriptions?.map((subscription) {
      return SyncStreamStatus._(subscription, downloadProgress);
    });
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

  /// If the [stream] appears in [activeSubscriptions], returns the current
  /// status for that stream.
  SyncStreamStatus? statusFor(SyncStreamDescription stream) {
    final raw = _internalSubscriptions?.firstWhereOrNull(
      (e) =>
          e.name == stream.name &&
          _mapEquality.equals(e.parameters, stream.parameters),
    );

    if (raw == null) {
      return null;
    }
    return SyncStreamStatus._(raw, downloadProgress);
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
      _listEquality.hash(priorityStatusEntries),
      downloadProgress,
      _listEquality.hash(_internalSubscriptions),
    );
  }

  @override
  String toString() {
    return "SyncStatus<connected: $connected connecting: $connecting downloading: $downloading (progress: $downloadProgress) uploading: $uploading lastSyncedAt: $lastSyncedAt, hasSynced: $hasSynced, error: $anyError>";
  }

  static const _listEquality = ListEquality<Object?>();
  static const _mapEquality = MapEquality<Object?, Object?>();
}

@internal
extension InternalSyncStatusAccess on SyncStatus {
  List<CoreActiveStreamSubscription>? get internalSubscriptions =>
      _internalSubscriptions;
}

final class SyncStreamStatus {
  final ProgressWithOperations? progress;
  final CoreActiveStreamSubscription _internal;

  SyncSubscriptionDefinition get subscription => _internal;
  StreamPriority get priority => _internal.priority;
  bool get isDefault => _internal.isDefault;

  SyncStreamStatus._(this._internal, SyncDownloadProgress? progress)
      : progress = progress?._internal._forStream(_internal);
}

@Deprecated('Use StreamPriority instead')
typedef BucketPriority = StreamPriority;

/// The priority of a PowerSync stream.
extension type const StreamPriority._(int priorityNumber) {
  static const _highest = 0;

  factory StreamPriority(int i) {
    assert(i >= _highest);
    return StreamPriority._(i);
  }

  bool operator >(StreamPriority other) => comparator(this, other) > 0;
  bool operator >=(StreamPriority other) => comparator(this, other) >= 0;
  bool operator <(StreamPriority other) => comparator(this, other) < 0;
  bool operator <=(StreamPriority other) => comparator(this, other) <= 0;

  /// A [Comparator] instance suitable for comparing [StreamPriority] values.
  static int comparator(StreamPriority a, StreamPriority b) =>
      -a.priorityNumber.compareTo(b.priorityNumber);

  /// The priority used by PowerSync to indicate that a full sync was completed.
  static const fullSyncPriority = StreamPriority._(2147483647);
}

/// Partial information about the synchronization status for buckets within a
/// priority.
typedef SyncPriorityStatus = ({
  StreamPriority priority,
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
  StreamPriority priority,
  int atLast,
  int sinceLast,
  int targetCount,
});

@internal
final class InternalSyncDownloadProgress extends ProgressWithOperations {
  final Map<String, BucketProgress> buckets;

  InternalSyncDownloadProgress(this.buckets)
      : super._(
          buckets.values.map((e) => e.targetCount - e.atLast).sum,
          buckets.values.map((e) => e.sinceLast).sum,
        );

  factory InternalSyncDownloadProgress.forNewCheckpoint(
      Map<String, LocalOperationCounters> localProgress, Checkpoint target) {
    final buckets = <String, BucketProgress>{};

    for (final bucket in target.checksums) {
      final savedProgress = localProgress[bucket.bucket];
      final atLast = savedProgress?.atLast ?? 0;
      final sinceLast = savedProgress?.sinceLast ?? 0;

      buckets[bucket.bucket] = (
        priority: BucketPriority._(bucket.priority),
        atLast: atLast,
        sinceLast: sinceLast,
        targetCount: bucket.count ?? 0,
      );

      if (bucket.count case final knownCount?) {
        if (knownCount < atLast + sinceLast) {
          // Either due to a defrag / sync rule deploy or a compaction
          // operation, the size of the bucket shrank so much that the local ops
          // exceed the ops in the updated bucket. We can't possibly report
          // progress in this case (it would overshoot 100%).
          return InternalSyncDownloadProgress({
            for (final bucket in target.checksums)
              bucket.bucket: (
                priority: BucketPriority(bucket.priority),
                atLast: 0,
                sinceLast: 0,
                targetCount: knownCount,
              )
          });
        }
      }
    }

    return InternalSyncDownloadProgress(buckets);
  }

  static InternalSyncDownloadProgress ofPublic(SyncDownloadProgress public) {
    return public._internal;
  }

  /// Sums the total target and completed operations for all buckets up until
  /// the given [priority] (inclusive).
  ProgressWithOperations untilPriority(BucketPriority priority) {
    final (total, downloaded) = buckets.values
        .where((e) => e.priority >= priority)
        .fold((0, 0), _addProgress);

    return ProgressWithOperations._(total, downloaded);
  }

  ProgressWithOperations _forStream(CoreActiveStreamSubscription subscription) {
    final (total, downloaded) = subscription.associatedBuckets.fold(
      (0, 0),
      (prev, bucket) {
        final foundProgress = buckets[bucket];
        if (foundProgress == null) {
          return prev;
        }

        return _addProgress(prev, foundProgress);
      },
    );

    return ProgressWithOperations._(total, downloaded);
  }

  InternalSyncDownloadProgress incrementDownloaded(SyncDataBatch batch) {
    final newBucketStates = Map.of(buckets);
    for (final dataForBucket in batch.buckets) {
      final previous = newBucketStates[dataForBucket.bucket]!;
      newBucketStates[dataForBucket.bucket] = (
        priority: previous.priority,
        atLast: previous.atLast,
        sinceLast: min(previous.sinceLast + dataForBucket.data.length,
            previous.targetCount - previous.atLast),
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
        // totalOperations and downloadedOperations are derived values, but
        // comparing them first helps find a difference faster.
        totalOperations == other.totalOperations &&
        downloadedOperations == other.downloadedOperations &&
        _mapEquality.equals(buckets, other.buckets);
  }

  @override
  String toString() {
    final all = asSyncDownloadProgress;
    return 'for total: ${all.downloadedOperations} / ${all.totalOperations}';
  }

  static const _mapEquality = MapEquality<Object?, Object?>();

  (int, int) _addProgress((int, int) prev, BucketProgress entry) {
    final downloaded = entry.sinceLast;
    final total = entry.targetCount - entry.atLast;
    return (prev.$1 + total, prev.$2 + downloaded);
  }
}

/// Information about a progressing download.
///
/// This reports the `total` amount of operations to download, how many of them
/// have already been `completed` and finally a `fraction` indicating relative
/// progress (as a number between `0.0` and `1.0`, inclusive)
///
/// To obtain these values, use [SyncDownloadProgress] available through
/// [SyncStatus.downloadProgress].
final class ProgressWithOperations {
  /// How many operations need to be downloaded in total until the current
  /// download is complete.
  final int totalOperations;

  /// How many operations have already been downloaded since the last complete
  /// download.
  final int downloadedOperations;

  ProgressWithOperations._(this.totalOperations, this.downloadedOperations);

  /// Relative progress (as a number between `0.0` and `1.0`).
  ///
  /// When this number reaches `1.0`, all changes have been received from the
  /// sync service. Actually applying these changes happens before the
  /// [SyncStatus.downloadProgress] flag is cleared though, so progress can stay
  /// at `1.0` for a short while before completing.
  double get downloadedFraction {
    return totalOperations == 0 ? 0.0 : downloadedOperations / totalOperations;
  }
}

/// Provides realtime progress on how PowerSync is downloading rows.
///
/// This type reports progress by implementing [ProgressWithOperations], meaning
/// that [downloadedOperations], [totalOperations] and [downloadedFraction] are
/// available on instances of [SyncDownloadProgress].
/// Additionally, it's possible to obtain the progress towards a specific
/// priority only (instead of tracking progress for the entire download) by
/// using [untilPriority].
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
extension type SyncDownloadProgress._(InternalSyncDownloadProgress _internal)
    implements ProgressWithOperations {
  /// Returns download progress towards all data up until the specified
  /// [priority] being received.
  ///
  /// The returned [ProgressWithOperations] tracks the target amount of
  /// operations that need to be downloaded in total and how many of them have
  /// already been received.
  ProgressWithOperations untilPriority(BucketPriority priority) {
    return _internal.untilPriority(priority);
  }
}
