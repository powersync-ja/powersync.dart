import 'dart:async';
import 'package:powersync/src/throttle.dart';
import 'package:test/test.dart';

void main() {
  group('throttle', () {
    test('should execute the function immediately on the first call', () async {
      int callCount = 0;

      testFunc() {
        callCount++;
        return 'Hello';
      }

      ThrottledFunction throttledFunction =
          throttle(testFunc, const Duration(milliseconds: 100));

      final result = await throttledFunction();
      expect(result, 'Hello');
      expect(callCount, 1);
    });

    test('should throttle subsequent calls within the given duration',
        () async {
      int callCount = 0;

      testFunc() {
        callCount++;
        return 'Hello';
      }

      ThrottledFunction throttledFunction =
          throttle(testFunc, const Duration(milliseconds: 100));

      await throttledFunction();
      await throttledFunction();
      await throttledFunction();

      expect(callCount, 1);
    });

    test('should execute the function after the throttle duration', () async {
      int callCount = 0;

      testFunc() {
        callCount++;
        return 'Hello';
      }

      ThrottledFunction throttledFunction =
          throttle(testFunc, const Duration(milliseconds: 100));

      await throttledFunction();
      await Future.delayed(const Duration(milliseconds: 200));
      await throttledFunction();

      expect(callCount, 2);
    });
  });
}
