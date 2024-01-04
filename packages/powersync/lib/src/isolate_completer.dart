import 'dart:async';
import 'dart:isolate';

class IsolateResult<T> {
  final ReceivePort receivePort = ReceivePort();
  late Future<T> future;

  IsolateResult() {
    final sendResult = receivePort.first;
    sendResult.whenComplete(() {
      receivePort.close();
    });

    future = sendResult.then((response) {
      if (response is PortResult) {
        return response.value as T;
      } else if (response == abortedResponse) {
        throw const IsolateTerminatedError();
      } else {
        throw AssertionError('Invalid response: $response');
      }
    });
  }

  PortCompleter<T> get completer {
    return PortCompleter(receivePort.sendPort);
  }

  close() {
    receivePort.close();
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
    sendPort.send(PortResult.error(error, stackTrace));
  }

  addExitHandler() {
    Isolate.current.addOnExitListener(sendPort, response: abortedResponse);
  }

  Future<void> handle(FutureOr<T> Function() callback,
      {bool ignoreStackTrace = false}) async {
    addExitHandler();
    try {
      final result = await callback();
      complete(result);
    } catch (error, stacktrace) {
      if (ignoreStackTrace) {
        completeError(error);
      } else {
        completeError(error, stacktrace);
      }
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

  T get value {
    if (success) {
      return _result as T;
    } else {
      if (_error != null && stackTrace != null) {
        Error.throwWithStackTrace(_error, stackTrace!);
      } else {
        throw _error!;
      }
    }
  }

  T get result {
    assert(success);
    return _result as T;
  }

  Object get error {
    assert(!success);
    return _error!;
  }
}

class IsolateTerminatedError implements Error {
  const IsolateTerminatedError();

  @override
  StackTrace? get stackTrace {
    return null;
  }
}
