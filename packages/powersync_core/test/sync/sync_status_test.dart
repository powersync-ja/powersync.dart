import 'package:powersync_core/powersync_core.dart';
import 'package:test/test.dart';

void main() {
  group('SyncStatus.toString', () {
    test('default', () {
      expect(SyncStatus().toString(),
          'SyncStatus<connected: offline (not connecting) downloading: false (progress: null) uploading: false lastSyncedAt: null hasSynced: null error: null>');
    });

    test('connection status', () {
      expect(SyncStatus(connected: true).toString(),
          contains('SyncStatus<connected: true'));
      expect(SyncStatus(connected: false, connecting: true).toString(),
          contains('SyncStatus<connected: connecting'));
      expect(SyncStatus().toString(),
          contains('SyncStatus<connected: offline (not connecting)'));
    });

    group('errors', () {
      test('upload error', () {
        expect(SyncStatus(uploadError: 'test').toString(),
            contains('uploadError: test'));
      });

      test('download error', () {
        expect(SyncStatus(downloadError: 'test').toString(),
            contains('downloadError: test'));
      });

      test('both upload and download error', () {
        expect(SyncStatus(uploadError: 'a', downloadError: 'b').toString(),
            contains('downloadError: b uploadError: a'));
      });

      test('no error', () {
        expect(SyncStatus().toString(), contains('error: null'));
      });
    });
  });
}
