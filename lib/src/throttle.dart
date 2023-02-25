import 'dart:async';

StreamTransformer<T, T> throttleTransformer<T>(Duration timeout) {
  Timer? timer;
  T? lastData;

  return StreamTransformer<T, T>.fromHandlers(handleData: (data, sink) {
    lastData = data;
    timer ??= Timer(timeout, () {
      sink.add(lastData as T);
      timer = null;
      lastData = null;
    });
  });
}
