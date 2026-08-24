import 'dart:async';
import 'dart:collection';

/// Controller to abort asynchronous requests or long-running tasks - either
/// before or after it started.
final class AbortController {
  /// True if an abort has been requested.
  bool get aborted => _defaultAbortListener.isCompleted;

  final Completer<void> _defaultAbortListener = Completer();
  final Set<Completer<void>> _abortListeners = LinkedHashSet.identity();

  final Completer<void> _abortCompleter = Completer();

  AbortController() {
    _abortListeners.add(_defaultAbortListener);
  }

  /// Future that is resolved when an abort has been requested.
  Future<void> get onAbort {
    return _defaultAbortListener.future;
  }

  Future<void> get onCompletion {
    return _abortCompleter.future;
  }

  /// Abort, and wait until aborting is complete.
  Future<void> abort() async {
    if (!_defaultAbortListener.isCompleted) {
      for (final listener in _abortListeners) {
        listener.complete();
      }

      _abortListeners.clear();
    }

    await onCompletion;
  }

  /// Signal that an abort has completed.
  void completeAbort() {
    if (!_abortCompleter.isCompleted) {
      _abortCompleter.complete();
    }
  }

  /// Signal that an abort has failed.
  /// Any calls to abort() will fail with this error.
  void abortError(Object error, [StackTrace? stackTrace]) {
    _abortCompleter.completeError(error, stackTrace);
  }

  /// Runs [block] with a future completing when this controller is aborted.
  ///
  /// The passed future is also completed when the block completes. This is
  /// more efficient than calling [Future.then] on [onAbort], as there's no way
  /// to remove that listener until the controller is aborted.
  Future<T> scoped<T>(Future<T> Function(Future<void> onAbort) block) {
    if (aborted) {
      return block(Future.syncValue(null));
    } else {
      final onAbort = Completer<void>();
      _abortListeners.add(onAbort);
      return Future(() => block(onAbort.future)).whenComplete(() {
        _abortListeners.remove(onAbort);
        if (!onAbort.isCompleted) onAbort.complete();
      });
    }
  }
}
