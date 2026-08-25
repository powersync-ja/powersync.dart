library;

import 'package:meta/meta.dart';

import '../database/powersync_database.dart';
import '../platform_specific/int64.dart';
import 'connection_manager.dart';
import 'sync_status.dart';

/// A checkpoint request created by [PowerSyncDatabase.requestCheckpoint].
///
/// Use this to wait until the local database has applied server-side changes up
/// to the requested checkpoint. This is useful for explicit refresh flows where
/// the caller wants confirmation that the local view has caught up to the
/// service.
///
/// Checkpoint requests are backed by request ids tracked in the local database,
/// so they are reusable across disconnect and reconnect cycles. A [waitForSync]
/// interrupted by a disconnect throws an error, but the same request can be
/// awaited again once a new connection is established.
///
/// Requests do not survive [PowerSyncDatabase.disconnectAndClear], instances
/// created before a clear should be discarded and requested again.
abstract final class CheckpointRequest {
  CheckpointRequest._();

  /// Whether this checkpoint request has synced before.
  @experimental
  bool get hasSynced;

  /// Waits until this checkpoint has been synced locally.
  ///
  /// This method faisl on sync errors: If a download or upload error occurs
  /// before this checkpoint request has synced, that error is rethrown here.
  /// This makes it easier to observe sync errors when relying on checkpoints.
  /// Once sync has recovered, it is valid to call this method again to await
  /// the checkpoint.
  @experimental
  Future<void> waitForSync({Future<void>? abortTrigger});
}

@internal
final class CheckpointRequestImpl extends CheckpointRequest {
  final Int64 _requestId;
  final ConnectionManager _connections;

  CheckpointRequestImpl(this._requestId, this._connections) : super._();

  @override
  bool get hasSynced {
    return _connections.currentStatus.hasApplied(_requestId);
  }

  @override
  Future<void> waitForSync({Future<void>? abortTrigger}) async {
    if (hasSynced) return;

    _connections.checkConnectedWithRequestsMode();

    await _connections.firstStatusMatching(abort: abortTrigger, (status) {
      if (status.hasApplied(_requestId)) return true;

      if (status.anyError case final anyError?) {
        throw CheckpointRequestException._(
          'Sync error while waiting for checkpoint request',
          anyError,
        );
      }

      if (!status.connected && !status.connecting) {
        throw disconnected;
      }

      return false;
    });
  }
}

/// An exception related to requested checkpoints for PowerSync.
final class CheckpointRequestException implements Exception {
  final String _message;
  final Object? cause;

  const CheckpointRequestException._(this._message, [this.cause]);

  @override
  String toString() {
    if (cause case final cause?) {
      return '$_message ($cause)';
    }

    return _message;
  }
}

@internal
const instanceNotSupported = CheckpointRequestException._(
  'The PowerSync service does not support checkpoint requests. Update to PowerSync service version 1.24.0 or later to use this API.',
);

@internal
const disconnected = CheckpointRequestException._(
  'Cannot request checkpoints, sync client is disconnected',
);

@internal
const disabled = CheckpointRequestException._(
  'Connected with legacy checkpoint mode, cannot request checkpoints',
);
