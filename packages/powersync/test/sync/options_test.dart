import 'package:powersync/src/sync/options.dart';
import 'package:test/test.dart';

void main() {
  group('sync options', () {
    test('can merge with changes', () {
      final a = ResolvedSyncOptions(SyncOptions(
        params: {'client': 'a'},
        crudThrottleTime: const Duration(seconds: 1),
      ));

      final (b, didChange) = a.applyFrom(SyncOptions(
        params: {'client': 'a'},
        retryDelay: const Duration(seconds: 1),
      ));

      expect(b.params, {'client': 'a'});
      expect(b.crudThrottleTime, const Duration(seconds: 1));
      expect(b.retryDelay, const Duration(seconds: 1));
      expect(didChange, isTrue);
    });

    test('can merge without changes', () {
      final a = ResolvedSyncOptions(SyncOptions(
        params: {'client': 'a'},
        crudThrottleTime: const Duration(seconds: 1),
      ));

      final (_, didChange) = a.applyFrom(SyncOptions(
        // This is the default, so no change from a
        retryDelay: const Duration(seconds: 5),
      ));

      expect(didChange, isFalse);
    });

    test('headers default to an empty map', () {
      final resolved = ResolvedSyncOptions(SyncOptions());
      expect(resolved.headers, isEmpty);
    });

    test('headers are preserved through resolve', () {
      final resolved = ResolvedSyncOptions(SyncOptions(
        headers: {'CF-Access-Client-Id': 'abc'},
      ));
      expect(resolved.headers, {'CF-Access-Client-Id': 'abc'});
    });

    test('changing headers triggers a reconnect', () {
      final a = ResolvedSyncOptions(SyncOptions(
        headers: {'CF-Access-Client-Id': 'abc'},
      ));

      final (b, didChange) = a.applyFrom(SyncOptions(
        headers: {'CF-Access-Client-Id': 'xyz'},
      ));

      expect(b.headers, {'CF-Access-Client-Id': 'xyz'});
      expect(didChange, isTrue);
    });
  });
}
