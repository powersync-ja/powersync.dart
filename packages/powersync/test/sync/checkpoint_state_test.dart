import 'dart:async';

import 'package:powersync/src/abort_controller.dart';
import 'package:powersync/src/sync/checkpoint_request.dart';
import 'package:powersync/src/sync/checkpoint_state.dart';
import 'package:sqlite_async/sqlite_async.dart';
import 'package:test/test.dart';

void main() {
  final neverAbort = Completer<void>().future;

  group('CheckpointStateSignals', () {
    group('waitForCheckpointrequestsReady', () {
      test('resolves immediately when already ready', () async {
        final signals = CheckpointStateSignals();
        signals.markCheckpointsReady(Future.syncValue(null));
        await signals.waitForCheckpointRequestsReady(abort: neverAbort);
      });

      test('rejects when disconnected', () async {
        final signals = CheckpointStateSignals();
        signals.disconnect();

        await expectLater(
          signals.waitForCheckpointRequestsReady(abort: neverAbort),
          throwsA(disconnected),
        );
      });

      test('rejects with the error', () async {
        final signals = CheckpointStateSignals();
        final error = Exception('expected init error');
        signals.markCheckpointsReady(Future.error(error)).ignore();

        await expectLater(
          signals.waitForCheckpointRequestsReady(abort: neverAbort),
          throwsA(error),
        );
      });

      test('can be aborted', () {
        final signals = CheckpointStateSignals();
        final abort = AbortController();

        final pending = signals.waitForCheckpointRequestsReady(
          abort: abort.onAbort,
        );
        abort.abort();

        expect(pending, throwsA(isA<AbortException>()));
      });

      test('supports concurrent waiters', () {
        final signals = CheckpointStateSignals();

        final first = signals.waitForCheckpointRequestsReady(abort: neverAbort);
        final second = signals.waitForCheckpointRequestsReady(
          abort: neverAbort,
        );

        signals.markCheckpointsReady(Future.syncValue(null));
        expect(first, completes);
        expect(second, completes);
      });
    });

    test(
      'waitForCheckpointWaiter is notified when a caller starts waiting while pending',
      () async {
        final signals = CheckpointStateSignals();

        final waiterNotified = signals.waitForCheckpointWaiter();
        signals.waitForCheckpointRequestsReady(abort: neverAbort);

        expect(waiterNotified, completes);
      },
    );

    test(
      'does not notify waitForCheckpointWaiter when wakeDownloadLoop is false',
      () async {
        final signals = CheckpointStateSignals();
        var didComplete = false;

        signals.waitForCheckpointWaiter().whenComplete(
          () => didComplete = true,
        );
        signals.waitForCheckpointRequestsReady(
          abort: neverAbort,
          wakeDownloadLoop: false,
        );

        await pumpEventQueue();
        expect(didComplete, isFalse);
      },
    );
  });
}
