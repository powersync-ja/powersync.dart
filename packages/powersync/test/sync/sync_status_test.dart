import 'package:powersync/powersync.dart';
import 'package:powersync/src/sync/instruction.dart';
import 'package:powersync/src/sync/status_update.dart';
import 'package:test/test.dart';

void main() {
  SyncStatus resolve(SyncStatusUpdate update) {
    return update.applyTo(const SyncStatus.uninitialized());
  }

  group('SyncStatus.toString', () {
    test('default', () {
      expect(
        SyncStatus.uninitialized().toString(),
        'SyncStatus<connected: offline (not connecting) downloading: false (progress: null) uploading: false lastSyncedAt: null hasSynced: null error: null>',
      );
    });

    test('connection status', () {
      expect(
        resolve(
          SyncStatusUpdate(
            core: CoreSyncStatus(
              originalJson: {},
              connected: true,
              connecting: false,
              priorityStatus: [],
              downloading: null,
              streams: [],
              lastAppliedCheckpointRequestId: null,
            ),
          ),
        ).toString(),
        contains('SyncStatus<connected: true'),
      );
      expect(
        resolve(
          SyncStatusUpdate(
            core: CoreSyncStatus(
              originalJson: {},
              connected: false,
              connecting: true,
              priorityStatus: [],
              downloading: null,
              streams: [],
              lastAppliedCheckpointRequestId: null,
            ),
          ),
        ).toString(),
        contains('SyncStatus<connected: connecting'),
      );
      expect(
        resolve(SyncStatusUpdate()).toString(),
        contains('SyncStatus<connected: offline (not connecting)'),
      );
    });

    group('errors', () {
      test('upload error', () {
        final status = resolve(SyncStatusUpdate(uploadError: 'test'));
        expect(status.toString(), contains('uploadError: test'));
      });

      test('download error', () {
        final status = resolve(SyncStatusUpdate(downloadError: 'test'));
        expect(status.toString(), contains('downloadError: test'));
      });

      test('both upload and download error', () {
        final status = resolve(
          SyncStatusUpdate(uploadError: 'a', downloadError: 'b'),
        );

        expect(status.toString(), contains('downloadError: b uploadError: a'));
      });

      test('no error', () {
        final withError = resolve(
          SyncStatusUpdate(uploadError: 'a', downloadError: 'b'),
        );
        final status = SyncStatusUpdate(
          uploadError: SyncStatusUpdate.resetSentinel,
          downloadError: SyncStatusUpdate.resetSentinel,
        );

        expect(status.applyTo(withError).toString(), contains('error: null'));
      });
    });
  });
}
