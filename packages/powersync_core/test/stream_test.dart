@TestOn('!browser')
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart';
import 'package:powersync_core/src/stream_utils.dart';
import 'package:test/test.dart';

void main() {
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

    test('addBroadcast - errors on cancel', () async {
      Object simulatedError = AssertionError('Closed');
      Stream<String> stream2 =
          genStream('S2:', Duration(milliseconds: 20)).asBroadcastStream();

      var controller = StreamController();
      var stream1 = controller.stream;

      var merged = addBroadcast(stream1, stream2);

      controller.add('S1: 0');
      controller.add('S1: 1');
      controller.add('S1: 2');
      controller.onCancel = () async {
        throw simulatedError;
      };

      List<String> result = [];
      Object? error;
      try {
        await for (var data in merged) {
          result.add(data);
          break;
        }
      } catch (e) {
        error = e;
      }
      expect(error, equals(simulatedError));
      expect(result.length, equals(1));
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

    test('ndjson', () async {
      var sourceData = '{"line": 1}\n{"line": 2}\n';
      var sourceBytes = Utf8Codec().encode(sourceData);
      var sourceStream = ByteStream.fromBytes(sourceBytes);
      var parsedStream = ndjson(sourceStream);
      var data = await parsedStream.toList();
      expect(
          data,
          equals([
            {"line": 1},
            {"line": 2}
          ]));
    });

    test('ndjson over Pipe', () async {
      final pipe = await Pipe.create();
      void writer() async {
        pipe.write.write('{"line":');
        await pipe.write.flush();
        pipe.write.write(' 1}\n{"line": 2}\n');
        await pipe.write.flush();
        await pipe.write.close();
      }

      writer();
      var parsedStream = ndjson(ByteStream(pipe.read));
      var data = await parsedStream.toList();
      expect(
          data,
          equals([
            {"line": 1},
            {"line": 2}
          ]));
    });

    test('ndjson with partial data', () async {
      final pipe = await Pipe.create();
      void writer() async {
        pipe.write.write('{"line": 1}\n{"line": 2');
        await pipe.write.flush();
        await pipe.write.close();
      }

      writer();
      var parsedStream = ndjson(ByteStream(pipe.read));

      List<Object?> result = [];
      Object? error;
      try {
        await for (var data in parsedStream) {
          result.add(data);
        }
      } catch (e) {
        error = e;
      }
      expect(
          result,
          equals([
            {"line": 1}
          ]));
      expect(error.toString(),
          startsWith('FormatException: Unexpected end of input'));
    });

    test('ndjson with partial data and merged stream', () async {
      final pipe = await Pipe.create();
      void writer() async {
        pipe.write.write('{"line": 1}\n{"line": 2');
        await pipe.write.flush();
        await pipe.write.close();
      }

      writer();
      var parsedStream = ndjson(ByteStream(pipe.read));

      Stream<String> stream2 =
          genStream('S2:', Duration(milliseconds: 50)).asBroadcastStream();

      var merged = addBroadcast(parsedStream, stream2);

      List<Object?> result = [];
      Object? error;
      try {
        await for (var data in merged) {
          result.add(data);
        }
      } catch (e) {
        error = e;
      }
      expect(
          result,
          equals([
            'S2: 0',
            {"line": 1}
          ]));
      expect(error.toString(),
          startsWith('FormatException: Unexpected end of input'));
    });
  });
}
