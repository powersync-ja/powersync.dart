import 'dart:async';
import 'dart:convert';

import 'package:meta/meta.dart';
import 'package:powersync_core/src/abort_controller.dart';
import 'package:powersync_core/src/connector.dart';
import 'package:powersync_core/src/database/active_instances.dart';
import 'package:powersync_core/src/database/powersync_db_mixin.dart';
import 'package:powersync_core/src/sync/options.dart';
import 'package:powersync_core/src/sync/stream.dart';
import 'package:powersync_core/src/sync/sync_status.dart';

import 'streaming_sync.dart';

/// A (stream name, JSON parameters) pair that uniquely identifies a stream
/// instantiation to subscribe to.
typedef _RawStreamKey = (String, String);

@internal
final class ConnectionManager {
  final PowerSyncDatabaseMixin db;
  final ActiveDatabaseGroup _activeGroup;

  /// All streams (with parameters) for which a subscription has been requested
  /// explicitly.
  final Map<_RawStreamKey, _ActiveSubscription> _locallyActiveSubscriptions =
      {};

  final StreamController<SyncStatus> _statusController =
      StreamController.broadcast();

  /// Fires when an entry is added or removed from [_locallyActiveSubscriptions]
  /// while we're connected.
  StreamController<void>? _subscriptionsChanged;

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
      _subscriptionsChanged?.close();
      _subscriptionsChanged = null;
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

  List<SubscribedStream> get _subscribedStreams => [
        for (final active in _locallyActiveSubscriptions.values)
          (name: active.name, parameters: active.encodedParameters)
      ];

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

    final subscriptionsChanged = StreamController<void>();

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
        initiallyActiveStreams: _subscribedStreams,
        activeStreams: subscriptionsChanged.stream.map((_) {
          return _subscribedStreams;
        }),
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
      _subscriptionsChanged = subscriptionsChanged;

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
        streamSubscriptions: status.internalSubscriptions,
      );

      // If the absence of hasSynced was the only difference, the new states
      // would be equal and don't require an event. So, check again.
      if (newStatus != currentStatus) {
        _currentStatus = newStatus;
        _statusController.add(currentStatus);
      }
    }
  }

  _SyncStreamSubscriptionHandle _referenceStreamSubscription(
      String stream, Map<String, Object?>? parameters) {
    final key = (stream, json.encode(parameters));
    _ActiveSubscription active;

    if (_locallyActiveSubscriptions[key] case final current?) {
      active = current;
    } else {
      active = _ActiveSubscription(this,
          name: stream, parameters: parameters, encodedParameters: key.$2);
      _locallyActiveSubscriptions[key] = active;
      _subscriptionsChanged?.add(null);
    }

    return _SyncStreamSubscriptionHandle(active);
  }

  void _clearSubscription(_ActiveSubscription subscription) {
    assert(subscription.refcount == 0);
    _locallyActiveSubscriptions
        .remove((subscription.name, subscription.encodedParameters));
    _subscriptionsChanged?.add(null);
  }

  Future<void> _subscriptionsCommand(Object? command) async {
    await db.writeTransaction((tx) {
      return tx.execute(
        'SELECT powersync_control(?, ?)',
        ['subscriptions', json.encode(command)],
      );
    });
    _subscriptionsChanged?.add(null);
  }

  Future<void> subscribe({
    required String stream,
    required Map<String, Object?>? parameters,
    Duration? ttl,
    StreamPriority? priority,
  }) async {
    await _subscriptionsCommand({
      'subscribe': {
        'stream': {
          'name': stream,
          'params': parameters,
        },
        'ttl': ttl?.inSeconds,
        'priority': priority,
      },
    });
  }

  Future<void> unsubscribeAll({
    required String stream,
    required Object? parameters,
  }) async {
    await _subscriptionsCommand({
      'unsubscribe': {
        'name': stream,
        'params': parameters,
      },
    });
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
  Future<SyncStreamSubscription> subscribe({
    Duration? ttl,
    StreamPriority? priority,
  }) async {
    await _connections.subscribe(
      stream: name,
      parameters: parameters,
      ttl: ttl,
      priority: priority,
    );

    return _connections._referenceStreamSubscription(name, parameters);
  }

  @override
  Future<void> unsubscribeAll() async {
    await _connections.unsubscribeAll(stream: name, parameters: parameters);
  }
}

final class _ActiveSubscription {
  final ConnectionManager connections;
  var refcount = 0;

  final String name;
  final String encodedParameters;
  final Map<String, Object?>? parameters;

  _ActiveSubscription(
    this.connections, {
    required this.name,
    required this.encodedParameters,
    required this.parameters,
  });

  void decrementRefCount() {
    refcount--;
    if (refcount == 0) {
      connections._clearSubscription(this);
    }
  }
}

final class _SyncStreamSubscriptionHandle implements SyncStreamSubscription {
  final _ActiveSubscription _source;

  _SyncStreamSubscriptionHandle(this._source) {
    _source.refcount++;

    // This is not unreliable, but can help decrementing refcounts on the inner
    // subscription when this handle is deallocated without [unsubscribe] being
    // called.
    _finalizer.attach(this, _source, detach: this);
  }

  @override
  String get name => _source.name;

  @override
  Map<String, Object?>? get parameters => _source.parameters;

  @override
  Future<void> unsubscribe() async {
    _finalizer.detach(this);
    _source.decrementRefCount();
  }

  @override
  Future<void> waitForFirstSync() async {
    return _source.connections.firstStatusMatching((status) {
      final currentProgress = status.statusFor(this);
      return currentProgress?.subscription.hasSynced ?? false;
    });
  }

  static final Finalizer<_ActiveSubscription> _finalizer =
      Finalizer((sub) => sub.decrementRefCount());
}
