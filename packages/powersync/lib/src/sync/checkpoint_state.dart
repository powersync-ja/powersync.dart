import 'dart:async';

import 'package:async/async.dart';
import 'package:sqlite_async/sqlite_async.dart' show AbortException;

import 'checkpoint_request.dart';

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

  Future<void> markCheckpointsReady(Future<void> initialization) async {
    final result = await Result.capture(initialization);
    _updateState(_CheckpointSeeded(result));

    // Rethrow errors (if there was one).
    return await result.asFuture;
  }

  /// Waits until a download iteration is active and has seeded the checkpoint
  /// state, meaning that checkpoint ids can safely be allocated.
  Future<void> waitForCheckpointRequestsReady({
    required Future<void> abort,
    bool wakeDownloadLoop = true,
  }) {
    final completer = Completer<void>();
    final subscription = _stateController.stream.listen(null);

    void handleState(_CheckpointState state) {
      switch (state) {
        case _Disconnected():
          completer.completeError(disconnected);
          subscription.cancel();
        case _CheckpointSeeded(:final result):
          completer.complete(result.asFuture);
          subscription.cancel();
        case _Pending():
          if (wakeDownloadLoop && !_waitingForWaiter.isCompleted) {
            _waitingForWaiter.complete();
          }
      }
    }

    subscription.onData(handleState);
    handleState(_currentState);

    abort.whenComplete(() {
      if (!completer.isCompleted) {
        completer.completeError(
          AbortException('waitForCheckpointRequestsReady'),
        );
        subscription.cancel();
      }
    });

    return completer.future;
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
