import 'dart:async';

typedef ThrottledFunction<T> = FutureOr<T> Function();

ThrottledFunction<T?> throttle<T>(
    FutureOr<T?> Function() originalFunction, Duration duration) {
  Timer? timer;
  bool shouldRun = true;

  void cancelTimer() {
    timer?.cancel();
    timer = null;
  }

  return () {
    cancelTimer();

    if (shouldRun) {
      shouldRun = false;
      final result = originalFunction();
      timer = Timer(duration, () {
        shouldRun = true;
      });
      return result;
    }
    return Future.value(null);
  };
}
