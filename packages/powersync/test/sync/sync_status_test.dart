import 'package:powersync/powersync.dart';
import 'package:powersync/src/sync/mutable_sync_status.dart';
import 'package:test/test.dart';

void main() {
  group('SyncStatus.toString', () {
    test('default', () {
      expect(
        SyncStatus.uninitialized().toString(),
        'SyncStatus<connected: offline (not connecting) downloading: false (progress: null) uploading: false lastSyncedAt: null hasSynced: null error: null>',
      );
    });

    test('connection status', () {
      expect(
        (MutableSyncStatus()..connected = true).immutableSnapshot().toString(),
        contains('SyncStatus<connected: true'),
      );
      expect(
        (MutableSyncStatus()..connecting = true).immutableSnapshot().toString(),
        contains('SyncStatus<connected: connecting'),
      );
      expect(
        (MutableSyncStatus()).immutableSnapshot().toString(),
        contains('SyncStatus<connected: offline (not connecting)'),
      );
    });

    group('errors', () {
      test('upload error', () {
        final status = (MutableSyncStatus()..uploadError = 'test')
            .immutableSnapshot();

        expect(status.toString(), contains('uploadError: test'));
      });

      test('download error', () {
        final status = (MutableSyncStatus()..downloadError = 'test')
            .immutableSnapshot();

        expect(status.toString(), contains('downloadError: test'));
      });

      test('both upload and download error', () {
        final status =
            (MutableSyncStatus()
                  ..uploadError = 'a'
                  ..downloadError = 'b')
                .immutableSnapshot();

        expect(status.toString(), contains('downloadError: b uploadError: a'));
      });

      test('no error', () {
        expect(
          MutableSyncStatus().immutableSnapshot().toString(),
          contains('error: null'),
        );
      });
    });
  });
}
