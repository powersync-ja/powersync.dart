import 'dart:async';

import 'package:async/async.dart';

import 'checkpoint_request.dart';
import 'stream_utils.dart';

final class CheckpointStateSignals {
  _CheckpointState _currentState = const _Pending();
  final _stateController = StreamController<_CheckpointState>.broadcast();

  Completer<void> _waitingForWaiter = Completer();

  void _updateState(_CheckpointState state) {
    _currentState = state;
    _stateController.add(state);
  }

  /// Marks the current download iteration as ended, blocking new checkpoint
  /// requests until the seed was performed in the next iteration.
  ///
  /// Returns a future that completes early once
  /// [waitForCheckpointRequestsReady] is called.
  void downloadIterationEnded() {
    // Checkpoint waiters called after this should be able to resume the
    // download iteration.
    _waitingForWaiter = Completer();
    _updateState(const _Pending());
  }

  /// Marks the sync client as disconnected, failing all outstanding checkpoint
  /// requests and preventing new ones.
  void disconnect() {
    _updateState(const _Disconnected());
  }

  /// Waits for a waiter wanting torequest a checkpoint.
  ///
  /// As the waiter is blocked for a seed run we start in the download
  /// iteration we use this to wake up the download iteration if it's currently
  /// paused.
  Future<void> waitForCheckpointWaiter() {
    return _waitingForWaiter.future;
  }

  void markCheckpointsReady() {
    _updateState(_CheckpointSeeded(Result.value(null)));
  }

  void markCheckpointsFailed(Object error, StackTrace trace) {
    _updateState(_CheckpointSeeded(Result.error(error, trace)));
  }

  /// Waits until a download iteration is active and has seeded the checkpoint
  /// state, meaning that checkpoint ids can safely be allocated.
  Future<void> waitForCheckpointRequestsReady({
    required Future<void> abort,
    bool wakeDownloadLoop = true,
  }) {
    return _stateController.stream.waitForFirstMatching(
      predicate: (state) {
        switch (state) {
          case _Disconnected():
            throw disconnected;
          case _CheckpointSeeded(:final result):
            if (result.asError case final error?) {
              Error.throwWithStackTrace(error.error, error.stackTrace);
            }
            return true;
          case _Pending():
            if (wakeDownloadLoop && !_waitingForWaiter.isCompleted) {
              _waitingForWaiter.complete();
            }
            return false;
        }
      },
      debugName: 'waitForCheckpointRequestsReady',
      abort: abort,
      current: _currentState,
    );
  }
}

sealed class _CheckpointState {
  const _CheckpointState();
}

final class _Pending extends _CheckpointState {
  const _Pending();
}

final class _CheckpointSeeded extends _CheckpointState {
  final Result<void> result;

  _CheckpointSeeded(this.result);
}

final class _Disconnected extends _CheckpointState {
  const _Disconnected();
}
