import 'package:meta/meta.dart';

import 'sync_status.dart';
import '../database/powersync_database.dart';

/// A description of a sync stream, consisting of its [name] and the
/// [parameters] used when subscribing.
abstract interface class SyncStreamDescription {
  /// The name of the stream as it appears in the stream definition for the
  /// PowerSync service.
  String get name;

  /// The parameters used to subscribe to the stream, if any.
  ///
  /// The same stream can be subscribed to multiple times with different
  /// parameters.
  Map<String, Object?>? get parameters;
}

/// Information about a subscribed sync stream.
///
/// This includes the [SyncStreamDescription] along with information about the
/// current sync status.
abstract interface class SyncSubscriptionDefinition
    extends SyncStreamDescription {
  /// Whether this stream is active, meaning that the subscription has been
  /// acknownledged by the sync serivce.
  bool get active;

  /// Whether this stream subscription is included by default, regardless of
  /// whether the stream has explicitly been subscribed to or not.
  ///
  /// It's possible for both [isDefault] and [hasExplicitSubscription] to be
  /// true at the same time - this happens when a default stream was subscribed
  /// explicitly.
  bool get isDefault;

  /// Whether this stream has been subscribed to explicitly.
  ///
  /// It's possible for both [isDefault] and [hasExplicitSubscription] to be
  /// true at the same time - this happens when a default stream was subscribed
  /// explicitly.
  bool get hasExplicitSubscription;

  /// For sync streams that have a time-to-live, the current time at which the
  /// stream would expire if not subscribed to again.
  DateTime? get expiresAt;

  /// Whether this stream subscription has been synced at least once.
  bool get hasSynced;

  /// If [hasSynced] is true, the last time data from this stream has been
  /// synced.
  DateTime? get lastSyncedAt;
}

/// A handle to a [SyncStreamDescription] that allows subscribing to the stream.
///
/// To obtain an instance of [SyncStream], call [PowerSyncDatabase.syncStream].
abstract interface class SyncStream extends SyncStreamDescription {
  /// Adds a subscription to this stream, requesting it to be included when
  /// connecting to the sync service.
  ///
  /// The [priority] can be used to override the priority of this stream.
  Future<SyncStreamSubscription> subscribe({
    Duration? ttl,
    StreamPriority? priority,
  });

  Future<void> unsubscribeAll();
}

/// A [SyncStream] that has been subscribed to.
abstract interface class SyncStreamSubscription
    implements SyncStreamDescription {
  /// A variant of [PowerSyncDatabase.waitForFirstSync] that is specific to
  /// this stream subscription.
  Future<void> waitForFirstSync();

  /// Removes this stream subscription from the database, if it has been
  /// subscribed to explicitly.
  ///
  /// The subscription may still be included for a while, until the client
  /// reconnects and receives new snapshots from the sync service.
  Future<void> unsubscribe();
}

/// An `ActiveStreamSubscription` as part of the sync status in Rust.
@internal
final class CoreActiveStreamSubscription implements SyncSubscriptionDefinition {
  @override
  final String name;
  @override
  final Map<String, Object?>? parameters;
  final StreamPriority priority;
  final List<String> associatedBuckets;
  @override
  final bool active;
  @override
  final bool isDefault;
  @override
  final bool hasExplicitSubscription;
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
    required this.hasExplicitSubscription,
    required this.expiresAt,
    required this.lastSyncedAt,
  });

  factory CoreActiveStreamSubscription.fromJson(Map<String, Object?> json) {
    return CoreActiveStreamSubscription._(
      name: json['name'] as String,
      parameters: json['parameters'] as Map<String, Object?>?,
      priority: switch (json['priority'] as int?) {
        final prio? => StreamPriority(prio),
        null => StreamPriority.fullSyncPriority,
      },
      associatedBuckets: (json['associated_buckets'] as List).cast(),
      active: json['active'] as bool,
      isDefault: json['is_default'] as bool,
      hasExplicitSubscription: json['has_explicit_subscription'] as bool,
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

  Map<String, Object?> toJson() {
    return {
      'name': name,
      'parameters': parameters,
      'priority': priority.priorityNumber,
      'associated_buckets': associatedBuckets,
      'active': active,
      'is_default': isDefault,
      'has_explicit_subscription': hasExplicitSubscription,
      'expires_at': switch (expiresAt) {
        null => null,
        final expiresAt => expiresAt.millisecondsSinceEpoch / 1000,
      },
      'last_synced_at': switch (lastSyncedAt) {
        null => null,
        final lastSyncedAt => lastSyncedAt.millisecondsSinceEpoch / 1000,
      }
    };
  }
}
