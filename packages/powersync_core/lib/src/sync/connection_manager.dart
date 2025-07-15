import 'dart:async';
import 'dart:convert';

import 'package:meta/meta.dart';
import 'package:powersync_core/powersync_core.dart';
import 'package:powersync_core/src/abort_controller.dart';
import 'package:powersync_core/src/database/active_instances.dart';
import 'package:powersync_core/src/database/powersync_db_mixin.dart';
import 'package:powersync_core/src/sync/options.dart';
import 'package:powersync_core/src/sync/stream.dart';

@internal
final class ConnectionManager {
  final PowerSyncDatabaseMixin db;
  final ActiveDatabaseGroup _activeGroup;

  final StreamController<SyncStatus> _statusController = StreamController();
  SyncStatus _currentStatus =
      const SyncStatus(connected: false, lastSyncedAt: null);

  SyncStatus get currentStatus => _currentStatus;
  Stream<SyncStatus> get statusStream => _statusController.stream;

  /// The abort controller for the current sync iteration.
  ///
  /// null when disconnected, present when connecting or connected.
  ///
  /// The controller must only be accessed from within a critical section of the
  /// sync mutex.
  AbortController? _abortActiveSync;

  /// Only to be called in the sync mutex.
  Future<void> Function()? _connectWithLastOptions;

  ConnectionManager(this.db) : _activeGroup = db.group;

  void checkNotConnected() {
    if (_abortActiveSync != null) {
      throw StateError('Cannot update schema while connected');
    }
  }

  Future<void> _abortCurrentSync() async {
    if (_abortActiveSync case final disconnector?) {
      /// Checking `disconnecter.aborted` prevents race conditions
      /// where multiple calls to `disconnect` can attempt to abort
      /// the controller more than once before it has finished aborting.
      if (disconnector.aborted == false) {
        await disconnector.abort();
        _abortActiveSync = null;
      } else {
        /// Wait for the abort to complete. Continue updating the sync status after completed
        await disconnector.onCompletion;
      }
    }
  }

  Future<void> disconnect() async {
    // Also wrap this in the sync mutex to ensure there's no race between us
    // connecting and disconnecting.
    await _activeGroup.syncConnectMutex.lock(() async {
      await _abortCurrentSync();
      _connectWithLastOptions = null;
    });

    manuallyChangeSyncStatus(
        SyncStatus(connected: false, lastSyncedAt: currentStatus.lastSyncedAt));
  }

  Future<void> firstStatusMatching(bool Function(SyncStatus) predicate) async {
    if (predicate(currentStatus)) {
      return;
    }
    await for (final result in statusStream) {
      if (predicate(result)) {
        break;
      }
    }
  }

  Future<void> reconnect() async {
    // Also wrap this in the sync mutex to ensure there's no race between us
    // connecting and disconnecting.
    await _activeGroup.syncConnectMutex.lock(() async {
      if (_connectWithLastOptions case final activeSync?) {
        await _abortCurrentSync();
        assert(_abortActiveSync == null);

        await activeSync();
      }
    });
  }

  Future<void> connect({
    required PowerSyncBackendConnector connector,
    required ResolvedSyncOptions options,
  }) async {
    if (db.schema.rawTables.isNotEmpty &&
        options.source.syncImplementation != SyncClientImplementation.rust) {
      throw UnsupportedError(
          'Raw tables are only supported by the Rust client.');
    }

    var thisConnectAborter = AbortController();
    final zone = Zone.current;

    late void Function() retryHandler;

    Future<void> connectWithSyncLock() async {
      // Ensure there has not been a subsequent connect() call installing a new
      // sync client.
      assert(identical(_abortActiveSync, thisConnectAborter));
      assert(!thisConnectAborter.aborted);

      // ignore: invalid_use_of_protected_member
      await db.connectInternal(
        connector: connector,
        options: options,
        abort: thisConnectAborter,
        // Run follow-up async tasks in the parent zone, a new one is introduced
        // while we hold the lock (and async tasks won't hold the sync lock).
        asyncWorkZone: zone,
      );

      thisConnectAborter.onCompletion.whenComplete(retryHandler);
    }

    // If the sync encounters a failure without being aborted, retry
    retryHandler = Zone.current.bindCallback(() async {
      _activeGroup.syncConnectMutex.lock(() async {
        // Is this still supposed to be active? (abort is only called within
        // mutex)
        if (!thisConnectAborter.aborted) {
          // We only change _abortActiveSync after disconnecting, which resets
          // the abort controller.
          assert(identical(_abortActiveSync, thisConnectAborter));

          // We need a new abort controller for this attempt
          _abortActiveSync = thisConnectAborter = AbortController();

          db.logger.warning('Sync client failed, retrying...');
          await connectWithSyncLock();
        }
      });
    });

    await _activeGroup.syncConnectMutex.lock(() async {
      // Disconnect a previous sync client, if one is active.
      await _abortCurrentSync();
      assert(_abortActiveSync == null);
      _connectWithLastOptions = connectWithSyncLock;

      // Install the abort controller for this particular connect call, allowing
      // it to be disconnected.
      _abortActiveSync = thisConnectAborter;
      await connectWithSyncLock();
    });
  }

  void manuallyChangeSyncStatus(SyncStatus status) {
    if (status != currentStatus) {
      final newStatus = SyncStatus(
        connected: status.connected,
        downloading: status.downloading,
        uploading: status.uploading,
        connecting: status.connecting,
        uploadError: status.uploadError,
        downloadError: status.downloadError,
        priorityStatusEntries: status.priorityStatusEntries,
        downloadProgress: status.downloadProgress,
        // Note that currently the streaming sync implementation will never set
        // hasSynced. lastSyncedAt implies that syncing has completed at some
        // point (hasSynced = true).
        // The previous values of hasSynced should be preserved here.
        lastSyncedAt: status.lastSyncedAt ?? currentStatus.lastSyncedAt,
        hasSynced: status.lastSyncedAt != null
            ? true
            : status.hasSynced ?? currentStatus.hasSynced,
      );

      // If the absence of hasSynced was the only difference, the new states
      // would be equal and don't require an event. So, check again.
      if (newStatus != currentStatus) {
        _currentStatus = newStatus;
        _statusController.add(currentStatus);
      }
    }
  }

  Future<void> _subscriptionsCommand(Object? command) async {
    await db.writeTransaction((tx) {
      return db.execute(
        'SELECT powersync_control(?, ?)',
        ['subscriptions', json.encode(command)],
      );
    });

    await reconnect();
  }

  Future<void> subscribe({
    required String stream,
    required Object? parameters,
    Duration? ttl,
    BucketPriority? priority,
  }) async {
    await _subscriptionsCommand({
      'subscribe': {
        'stream': stream,
        'params': parameters,
        'ttl': ttl?.inSeconds,
        'priority': priority,
      },
    });
  }

  Future<void> unsubscribe({
    required String stream,
    required Object? parameters,
    required bool immediate,
  }) async {
    await _subscriptionsCommand({
      'unsubscribe': {
        'stream': stream,
        'params': parameters,
        'immediate': immediate,
      },
    });
  }

  Future<SyncStreamSubscription?> resolveCurrent(
      String name, Map<String, Object?>? parameters) async {
    final row = await db.getOptional(
      'SELECT stream_name, active, is_default, local_priority, local_params, expires_at, last_synced_at, ttl FROM ps_stream_subscriptions WHERE stream_name = ? AND local_params = ?',
      [name, json.encode(parameters)],
    );

    if (row == null) {
      return null;
    }

    return _SyncStreamSubscription(
      this,
      name: name,
      parameters:
          json.decode(row['local_params'] as String) as Map<String, Object?>?,
      active: row['active'] != 0,
      isDefault: row['is_default'] != 0,
      hasExplicitSubscription: row['ttl'] != null,
      expiresAt: switch (row['expires_at']) {
        null => null,
        final expiresAt as int =>
          DateTime.fromMicrosecondsSinceEpoch(expiresAt * 1000),
      },
      hasSynced: row['has_synced'] != 0,
      lastSyncedAt: switch (row['last_synced_at']) {
        null => null,
        final lastSyncedAt as int =>
          DateTime.fromMicrosecondsSinceEpoch(lastSyncedAt * 1000),
      },
    );
  }

  SyncStream syncStream(String name, Map<String, Object?>? parameters) {
    return _SyncStreamImplementation(this, name, parameters);
  }

  void close() {
    _statusController.close();
  }
}

final class _SyncStreamImplementation implements SyncStream {
  @override
  final String name;

  @override
  final Map<String, Object?>? parameters;

  final ConnectionManager _connections;

  _SyncStreamImplementation(this._connections, this.name, this.parameters);

  @override
  Future<SyncStreamSubscription?> get current {
    return _connections.resolveCurrent(name, parameters);
  }

  @override
  Future<void> subscribe({
    Duration? ttl,
    BucketPriority? priority,
  }) async {
    await _connections.subscribe(
      stream: name,
      parameters: parameters,
      ttl: ttl,
      priority: priority,
    );
  }
}

final class _SyncStreamSubscription implements SyncStreamSubscription {
  final ConnectionManager _connections;

  @override
  final String name;
  @override
  final Map<String, Object?>? parameters;

  @override
  final bool active;
  @override
  final bool isDefault;
  @override
  final bool hasExplicitSubscription;
  @override
  final DateTime? expiresAt;
  @override
  final bool hasSynced;
  @override
  final DateTime? lastSyncedAt;

  _SyncStreamSubscription(
    this._connections, {
    required this.name,
    required this.parameters,
    required this.active,
    required this.isDefault,
    required this.hasExplicitSubscription,
    required this.expiresAt,
    required this.hasSynced,
    required this.lastSyncedAt,
  });

  @override
  Future<void> unsubscribe({bool immediately = false}) async {
    await _connections.unsubscribe(
        stream: name, parameters: parameters, immediate: immediately);
  }

  @override
  Future<void> waitForFirstSync() async {
    if (hasSynced) {
      return;
    }
    return _connections.firstStatusMatching((status) {
      final currentProgress = status.statusFor(this);
      return currentProgress?.subscription.hasSynced ?? false;
    });
  }
}
