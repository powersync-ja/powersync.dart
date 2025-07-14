import 'package:meta/meta.dart';

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
  DateTime? get lastSyncedAt;
}

abstract interface class SyncStream extends SyncStreamDescription {
  Future<void> subscribe({
    Duration? ttl,
    BucketPriority? priority,
    Map<String, Object?>? parameters,
  });

  Future<SyncStreamSubscription?> get current;
}

abstract interface class SyncStreamSubscription
    implements SyncStreamDescription, SyncSubscriptionDefinition {
  Future<void> waitForFirstSync();
  Future<void> unsubscribe({bool immediately = false});
}

/// An `ActiveStreamSubscription` as part of the sync status in Rust.
@internal
final class CoreActiveStreamSubscription implements SyncSubscriptionDefinition {
  @override
  final String name;
  @override
  final Map<String, Object?>? parameters;
  final BucketPriority priority;
  final List<String> associatedBuckets;
  @override
  final bool active;
  final bool isDefault;
  @override
  final DateTime? expiresAt;
  @override
  final DateTime? lastSyncedAt;

  @override
  bool get hasSynced => lastSyncedAt != null;

  CoreActiveStreamSubscription._({
    required this.name,
    required this.parameters,
    required this.priority,
    required this.associatedBuckets,
    required this.active,
    required this.isDefault,
    required this.expiresAt,
    required this.lastSyncedAt,
  });

  factory CoreActiveStreamSubscription.fromJson(Map<String, Object?> json) {
    return CoreActiveStreamSubscription._(
      name: json['name'] as String,
      parameters: json['parameters'] as Map<String, Object?>,
      priority: BucketPriority(json['priority'] as int),
      associatedBuckets: (json['associated_buckets'] as List).cast(),
      active: json['active'] as bool,
      isDefault: json['is_default'] as bool,
      expiresAt: switch (json['expires_at']) {
        null => null,
        final timestamp as int =>
          DateTime.fromMillisecondsSinceEpoch(timestamp * 1000),
      },
      lastSyncedAt: switch (json['last_synced_at']) {
        null => null,
        final timestamp as int =>
          DateTime.fromMillisecondsSinceEpoch(timestamp * 1000),
      },
    );
  }
}
