import 'dart:async';

import 'package:powersync_core/src/sync/sync_status.dart';
import 'package:powersync_core/src/sync/protocol.dart';
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

    test('does not combine large batches', () async {
      final source = StreamController<Map<String, dynamic>>();
      expect(
        source.stream.transform(StreamingSyncLine.reader),
        emitsInOrder([
          isA<SyncDataBatch>()
              .having((e) => e.totalOperations, 'totalOperations', 1),
          isA<SyncDataBatch>()
              .having((e) => e.totalOperations, 'totalOperations', 150),
        ]),
      );

      source
        ..add({
          'data': {
            'bucket': 'a',
            'data': <Map<String, Object?>>[
              {
                'op_id': '0',
                'op': 'PUT',
                'object_type': 'a',
                'object_id': '0',
                'checksum': 0,
                'data': {},
              }
            ],
            'hasMore': false
          }
        })
        ..add({
          'data': {
            'bucket': 'a',
            'data': <Map<String, Object?>>[
              for (var i = 1; i <= 150; i++)
                {
                  'op_id': '$i',
                  'op': 'PUT',
                  'object_type': 'a',
                  'object_id': '$i',
                  'checksum': 0,
                  'data': {},
                }
            ],
            'hasMore': false
          }
        });
    });

    test('flushes when internal buffer gets too large', () {
      final source = StreamController<Map<String, dynamic>>();
      expect(
        source.stream.transform(StreamingSyncLine.reader),
        emitsInOrder([
          isA<SyncDataBatch>()
              .having((e) => e.totalOperations, 'totalOperations', 1000),
          isA<SyncDataBatch>()
              .having((e) => e.totalOperations, 'totalOperations', 500),
        ]),
      );

      // Add 1500 operations in chunks of 100 items. This should emit an
      // 1000-item chunk and another one for the rest.
      for (var i = 0; i < 15; i++) {
        source.add({
          'data': {
            'bucket': 'a',
            'data': <Map<String, Object?>>[
              for (var i = 0; i < 100; i++)
                {
                  'op_id': '1',
                  'op': 'PUT',
                  'object_type': 'a',
                  'object_id': '1',
                  'checksum': 0,
                  'data': {},
                }
            ],
            'hasMore': false
          }
        });
      }
    });

    test('stream priority comparisons', () {
      expect(StreamPriority(0) < StreamPriority(3), isFalse);
      expect(StreamPriority(0) > StreamPriority(3), isTrue);
      expect(StreamPriority(0) >= StreamPriority(3), isTrue);
      expect(StreamPriority(0) >= StreamPriority(0), isTrue);
    });
  });
}
