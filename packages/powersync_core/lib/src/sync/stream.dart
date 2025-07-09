import 'sync_status.dart';

abstract interface class SyncStreamDescription {
  String get name;
  Map<String, Object?>? get parameters;
}

abstract interface class SyncSubscriptionDefinition
    extends SyncStreamDescription {
  bool get active;
  DateTime? get expiresAt;
  bool get hasSynced;
  DateTime? lastSyncedAt;
}

abstract interface class SyncStream extends SyncStreamDescription {
  Future<void> subscribe({
    Duration? ttl,
    BucketPriority? priority,
    Map<String, Object?>? parameters,
  });
}

abstract interface class SyncStreamSubscription
    implements SyncStreamDescription, SyncSubscriptionDefinition {
  Future<void> waitForFirstSync();
  Future<void> unsubscribe({bool immediately = false});
}
