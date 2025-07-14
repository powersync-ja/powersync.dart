import 'dart:async';

import 'package:meta/meta.dart';
import 'package:powersync_core/powersync_core.dart';
import 'package:powersync_core/src/abort_controller.dart';
import 'package:powersync_core/src/database/active_instances.dart';
import 'package:powersync_core/src/database/powersync_db_mixin.dart';
import 'package:powersync_core/src/sync/options.dart';

@internal
final class ConnectionManager {
  final PowerSyncDatabaseMixin db;
  final StreamController<SyncStatus> _statusController = StreamController();

  SyncStatus _currentStatus =
      const SyncStatus(connected: false, lastSyncedAt: null);

  SyncStatus get currentStatus => _currentStatus;
  Stream<SyncStatus> get statusStream => _statusController.stream;

  final ActiveDatabaseGroup _activeGroup;

  ConnectionManager(this.db) : _activeGroup = db.group;

  /// The abort controller for the current sync iteration.
  ///
  /// null when disconnected, present when connecting or connected.
  ///
  /// The controller must only be accessed from within a critical section of the
  /// sync mutex.
  @protected
  AbortController? _abortActiveSync;

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
    await _activeGroup.syncConnectMutex.lock(_abortCurrentSync);

    manuallyChangeSyncStatus(
        SyncStatus(connected: false, lastSyncedAt: currentStatus.lastSyncedAt));
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

  void close() {
    _statusController.close();
  }
}
