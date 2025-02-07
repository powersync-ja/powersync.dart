import 'dart:async';

import 'package:powersync_core/src/sync_types.dart';
import 'package:test/test.dart';

void main() {
  group('Sync types', () {
    test('parses JSON stream', () {
      final source = StreamController<Map<String, dynamic>>();
      expect(
        source.stream.transform(StreamingSyncLine.reader),
        emitsInOrder([
          isA<StreamingSyncKeepalive>(),
          isA<SyncDataBatch>(),
          isA<StreamingSyncCheckpointComplete>(),
          isA<Checkpoint>(),
          isA<StreamingSyncCheckpointDiff>(),
          isA<UnknownSyncLine>(),
          emitsDone,
        ]),
      );

      source
        ..add({'token_expires_in': 10})
        ..add({
          'data': {
            'bucket': 'a',
            'data': <Map<String, Object?>>[],
            'hasMore': false
          }
        })
        ..add({
          'checkpoint_complete': {'last_op_id': '10'}
        })
        ..add({
          'checkpoint': {
            'last_op_id': '10',
            'write_checkpoint': null,
            'buckets': <Map<String, Object?>>[],
          }
        })
        ..add({
          'checkpoint_diff': {
            'last_op_id': '10',
            'write_checkpoint': null,
            'updated_buckets': <Map<String, Object?>>[],
            'removed_buckets': <Map<String, Object?>>[],
          }
        })
        ..add({'invalid_line': ''})
        ..close();
    });

    test('can group data lines', () {
      final source = StreamController<Map<String, dynamic>>();
      expect(
        source.stream.transform(StreamingSyncLine.reader),
        emits(
          isA<SyncDataBatch>()
              .having((e) => e.buckets, 'buckets', hasLength(2)),
        ),
      );

      source
        ..add({
          'data': {
            'bucket': 'a',
            'data': <Map<String, Object?>>[],
            'hasMore': false
          }
        })
        ..add({
          'data': {
            'bucket': 'b',
            'data': <Map<String, Object?>>[],
            'hasMore': false
          }
        });
    });

    test('flushes pending data lines before closing', () {
      final source = StreamController<Map<String, dynamic>>();
      expect(
        source.stream.transform(StreamingSyncLine.reader),
        emitsInOrder([
          isA<SyncDataBatch>(),
          emitsDone,
        ]),
      );

      source
        ..add({
          'data': {
            'bucket': 'a',
            'data': <Map<String, Object?>>[],
            'hasMore': false
          }
        })
        ..close();
    });

    test('data line grouping keeps order', () {
      final source = StreamController<Map<String, dynamic>>();
      expect(
        source.stream.transform(StreamingSyncLine.reader),
        emitsInOrder([
          isA<SyncDataBatch>(),
          isA<StreamingSyncCheckpointComplete>(),
          isA<SyncDataBatch>(),
          emitsDone,
        ]),
      );

      source
        ..add({
          'data': {
            'bucket': 'a',
            'data': <Map<String, Object?>>[],
            'hasMore': false
          }
        })
        ..add({
          'checkpoint_complete': {'last_op_id': '10'}
        })
        ..add({
          'data': {
            'bucket': 'b',
            'data': <Map<String, Object?>>[],
            'hasMore': false
          }
        })
        ..close();
    });
  });
}
