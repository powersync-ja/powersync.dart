import 'package:powersync/src/stream_utils.dart';
import 'package:test/test.dart';

import 'util.dart';

void main() {
  setupLogger();

  group('Stream Tests', () {
    setUp(() async {});

    tearDown(() async {});

    Stream<String> genStream(String prefix, Duration delay,
        [int count = 50, Object? error]) async* {
      for (var i = 0; i < count; i++) {
        yield "$prefix $i";
        await Future.delayed(delay);
      }
      if (error != null) {
        throw error;
      }
    }

    test('addBroadcast - basic', () async {
      Stream<String> stream1 = genStream('S1:', Duration(milliseconds: 5));
      Stream<String> stream2 =
          genStream('S2:', Duration(milliseconds: 20)).asBroadcastStream();

      var merged = addBroadcast(stream1, stream2);

      var data = await merged.take(20).toList();
      var countS1 =
          data.where((element) => element.startsWith('S1')).toList().length;
      var countS2 =
          data.where((element) => element.startsWith('S2')).toList().length;
      expect(countS1 + countS2, equals(20));
      expect(countS1, greaterThanOrEqualTo(10));
      expect(countS2, greaterThanOrEqualTo(0));
    });

    test('addBroadcast - errors', () async {
      Object simulatedError = AssertionError('Closed');
      Stream<String> stream1 =
          genStream('S1:', Duration(milliseconds: 5), 5, simulatedError);
      Stream<String> stream2 =
          genStream('S2:', Duration(milliseconds: 20)).asBroadcastStream();

      var merged = addBroadcast(stream1, stream2);

      List<String> result = [];
      Object? error;
      try {
        await for (var data in merged) {
          result.add(data);
        }
      } catch (e) {
        error = e;
      }
      expect(error, equals(simulatedError));
      expect(result.length, greaterThanOrEqualTo(5));
    });

    test('addBroadcast - re-use broadcast after error', () async {
      Object simulatedError = AssertionError('Closed');
      Stream<String> stream1 =
          genStream('S1:', Duration(milliseconds: 5), 5, simulatedError);
      Stream<String> sb =
          genStream('SB:', Duration(milliseconds: 20)).asBroadcastStream();

      var merged = addBroadcast(stream1, sb);

      List<String> result = [];
      Object? error;
      try {
        await for (var data in merged) {
          result.add(data);
        }
      } catch (e) {
        error = e;
      }
      expect(error, equals(simulatedError));
      expect(result.length, greaterThanOrEqualTo(5));

      Stream<String> stream3 = genStream('S3:', Duration(milliseconds: 5));

      var merged2 = addBroadcast(stream3, sb);

      var data = await merged2.take(20).toList();
      var countS1 =
          data.where((element) => element.startsWith('S3')).toList().length;
      var countS2 =
          data.where((element) => element.startsWith('SB')).toList().length;
      expect(countS1 + countS2, equals(20));
      expect(countS1, greaterThanOrEqualTo(10));
      expect(countS2, greaterThanOrEqualTo(0));
    });
  });
}
