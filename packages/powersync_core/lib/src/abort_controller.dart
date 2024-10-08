import 'dart:async';

/// Controller to abort asynchronous requests or long-running tasks - either
/// before or after it started.
class AbortController {
  /// True if an abort has been requested.
  bool aborted = false;

  final Completer<void> _abortRequested = Completer();
  final Completer<void> _abortCompleter = Completer();

  /// Future that is resolved when an abort has been requested.
  Future<void> get onAbort {
    return _abortRequested.future;
  }

  /// Abort, and wait until aborting is complete.
  Future<void> abort() async {
    aborted = true;
    if (!_abortRequested.isCompleted) {
      _abortRequested.complete();
    }

    await _abortCompleter.future;
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
}
