@TestOn('!browser')
library;

import 'dart:async';

import 'package:powersync/src/isolate_completer.dart';
import 'package:test/test.dart';

void main() {
  group('IsolateResultCollection', () {
    late IsolateResultCollection collection;

    setUp(() {
      collection = IsolateResultCollection();
    });

    test('pending result resolves with success value', () async {
      final result = collection.createPending<String>();
      result.completer.complete('hello');

      expect(await result.future, 'hello');
    });

    test('pending result resolves with error', () async {
      final result = collection.createPending<String>();
      result.completer.completeError(ArgumentError('expected for test'));

      await expectLater(result.future, throwsArgumentError);
    });

    test('close() before response throws StateError on future', () async {
      final result = collection.createPending<String>();
      expectLater(result.future, throwsStateError);

      collection.close();
    });

    test('close() aborts all in-flight results', () async {
      final a = collection.createPending<int>();
      final b = collection.createPending<String>();
      final c = collection.createPending<void>();

      expectLater(a.future, throwsStateError);
      expectLater(b.future, throwsStateError);
      expectLater(c.future, throwsStateError);
      collection.close();
    });

    test('close() after result resolves is a no-op', () async {
      final result = collection.createPending<int>();
      result.completer.complete(42);
      await result.future;

      // Closing a collection with no pending results should not throw.
      collection.close();
    });

    test('createPending() on a closed collection throws', () {
      collection.close();

      expect(() => collection.createPending<int>(), throwsStateError);
    });
  });

  group('PortCompleter.handle', () {
    late IsolateResultCollection collection;

    setUp(() {
      collection = IsolateResultCollection();
    });

    test('handle() completes the future on success', () async {
      final result = collection.createPending<int>();
      unawaited(result.completer.handle(() async => 7));

      expect(await result.future, 7);
    });

    test('handle() forwards errors to the future', () async {
      final result = collection.createPending<int>();
      unawaited(
        result.completer.handle(() => throw ArgumentError('expected for test')),
      );

      await expectLater(result.future, throwsArgumentError);
    });
  });
}
