import 'package:powersync_core/powersync_core.dart';
import 'package:powersync_core/src/sync/protocol.dart';
import 'package:test/test.dart';

TypeMatcher<SyncStatus> isSyncStatus({
  Object? downloading,
  Object? connected,
  Object? connecting,
  Object? hasSynced,
  Object? downloadProgress,
  Object? activeSubscriptions,
}) {
  var matcher = isA<SyncStatus>();
  if (downloading != null) {
    matcher = matcher.having((e) => e.downloading, 'downloading', downloading);
  }
  if (connected != null) {
    matcher = matcher.having((e) => e.connected, 'connected', connected);
  }
  if (connecting != null) {
    matcher = matcher.having((e) => e.connecting, 'connecting', connecting);
  }
  if (hasSynced != null) {
    matcher = matcher.having((e) => e.hasSynced, 'hasSynced', hasSynced);
  }
  if (downloadProgress != null) {
    matcher = matcher.having(
        (e) => e.downloadProgress, 'downloadProgress', downloadProgress);
  }
  if (activeSubscriptions != null) {
    matcher = matcher.having((e) => e.activeSubscriptions,
        'activeSubscriptions', activeSubscriptions);
  }

  return matcher;
}

TypeMatcher<SyncDownloadProgress> isSyncDownloadProgress({
  required Object progress,
  Map<StreamPriority, Object> priorities = const {},
}) {
  var matcher =
      isA<SyncDownloadProgress>().having((e) => e, 'untilCompletion', progress);
  priorities.forEach((priority, expected) {
    matcher = matcher.having(
        (e) => e.untilPriority(priority), 'untilPriority($priority)', expected);
  });

  return matcher;
}

TypeMatcher<ProgressWithOperations> progress(int completed, int total) {
  return isA<ProgressWithOperations>()
      .having((e) => e.downloadedOperations, 'completed', completed)
      .having((e) => e.totalOperations, 'total', total);
}

TypeMatcher<SyncStreamStatus> isStreamStatus({
  required Object? subscription,
  Object? progress,
}) {
  var matcher = isA<SyncStreamStatus>()
      .having((e) => e.subscription, 'subscription', subscription);
  if (progress case final progress?) {
    matcher = matcher.having((e) => e.progress, 'progress', progress);
  }

  return matcher;
}

TypeMatcher<SyncSubscriptionDescription> isSyncSubscription({
  required Object name,
  required Object? parameters,
  bool? isDefault,
}) {
  var matcher = isA<SyncSubscriptionDescription>()
      .having((e) => e.name, 'name', name)
      .having((e) => e.parameters, 'parameters', parameters);

  if (isDefault != null) {
    matcher = matcher.having((e) => e.isDefault, 'isDefault', isDefault);
  }

  return matcher;
}

BucketChecksum checksum(
    {required String bucket, required int checksum, int priority = 1}) {
  return BucketChecksum(bucket: bucket, priority: priority, checksum: checksum);
}

/// Creates a `checkpoint` line.
Object checkpoint({
  required int lastOpId,
  List<Object> buckets = const [],
  String? writeCheckpoint,
  List<Object> streams = const [],
}) {
  return {
    'checkpoint': {
      'last_op_id': '$lastOpId',
      'write_checkpoint': null,
      'buckets': buckets,
      'streams': streams,
    }
  };
}

Object stream(String name, bool isDefault, {List<Object> errors = const []}) {
  return {'name': name, 'is_default': isDefault, 'errors': errors};
}

/// Creates a `checkpoint_complete` or `partial_checkpoint_complete` line.
Object checkpointComplete({int? priority, String lastOpId = '1'}) {
  return {
    priority == null ? 'checkpoint_complete' : 'partial_checkpoint_complete': {
      'last_op_id': lastOpId,
      if (priority != null) 'priority': priority,
    },
  };
}

Object bucketDescription(
  String name, {
  int checksum = 0,
  int priority = 3,
  int count = 1,
  Object? subscriptions,
}) {
  return {
    'bucket': name,
    'checksum': checksum,
    'priority': priority,
    'count': count,
    if (subscriptions != null) 'subscriptions': subscriptions,
  };
}
