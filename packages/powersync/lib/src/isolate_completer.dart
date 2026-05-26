import 'dart:async';
import 'dart:isolate';

/// A collection of [IsolateResult]s that can be closed at once.
final class IsolateResultCollection {
  final Set<IsolateResult<void>> _inflight = {};
  bool _closed = false;

  IsolateResult<T> createPending<T>() {
    if (_closed) throw StateError('IsolateResultCollection is closed!');

    final result = IsolateResult<T>._(this);
    _inflight.add(result);
    return result;
  }

  void close() {
    if (!_closed) {
      _closed = true;

      for (final pending in _inflight) {
        pending.close();
      }

      _inflight.clear();
    }
  }
}

class IsolateResult<T> {
  final ReceivePort receivePort = ReceivePort('pending IsolateResult');
  final Completer<T> _completer = Completer.sync();

  Future<T> get future => _completer.future;

  IsolateResult._(IsolateResultCollection collection) {
    receivePort.first.then((response) {
      receivePort.close();
      collection._inflight.remove(this);

      if (response case final PortResult<dynamic> result) {
        result._applyTo(_completer);
      } else if (response == abortedResponse) {
        _completer.completeError(const IsolateTerminatedError());
      } else {
        _completer.completeError(AssertionError('Invalid response: $response'));
      }
    });
  }

  PortCompleter<T> get completer {
    return PortCompleter(receivePort.sendPort);
  }

  void close() {
    receivePort.close();
    if (!_completer.isCompleted) {
      completer.completeError(StateError('Closed before receiving response'));
    }
  }
}

const abortedResponse = 'aborted';

class PortCompleter<T> {
  final SendPort sendPort;

  PortCompleter(this.sendPort);

  void complete([FutureOr<T>? value]) {
    sendPort.send(PortResult.success(value));
  }

  void completeError(Object error, [StackTrace? stackTrace]) {
    sendPort.send(PortResult<void>.error(error, stackTrace));
  }

  Future<void> handle(FutureOr<T> Function() callback,
      {bool ignoreStackTrace = false}) async {
    Isolate.current.addOnExitListener(sendPort, response: abortedResponse);

    try {
      final result = await callback();
      complete(result);
    } catch (error, stacktrace) {
      if (ignoreStackTrace) {
        completeError(error);
      } else {
        completeError(error, stacktrace);
      }
    } finally {
      Isolate.current.removeOnExitListener(sendPort);
    }
  }
}

class PortResult<T> {
  final bool success;
  final T? _result;
  final Object? _error;
  final StackTrace? stackTrace;

  const PortResult.success(T result)
      : success = true,
        _error = null,
        stackTrace = null,
        _result = result;
  const PortResult.error(Object error, [this.stackTrace])
      : success = false,
        _result = null,
        _error = error;

  void _applyTo(Completer<dynamic> completer) {
    if (success) {
      completer.complete(_result);
    } else {
      completer.completeError(_error!, stackTrace);
    }
  }
}

class IsolateTerminatedError implements Error {
  const IsolateTerminatedError();

  @override
  StackTrace? get stackTrace {
    return null;
  }
}
