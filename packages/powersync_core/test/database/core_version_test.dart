import 'package:powersync_core/src/database/core_version.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:test/test.dart';

void main() {
  group('PowerSyncCoreVersion', () {
    test('parse', () {
      expect(PowerSyncCoreVersion.parse('0.3.9/5d64f366'), (0, 3, 9));
    });

    test('compare', () {
      void expectLess(String a, String b) {
        final parsedA = PowerSyncCoreVersion.parse(a);
        final parsedB = PowerSyncCoreVersion.parse(b);

        expect(parsedA.compareTo(parsedB), -1);
        expect(parsedB.compareTo(parsedA), 1);

        expect(parsedA.compareTo(parsedA), 0);
        expect(parsedB.compareTo(parsedB), 0);
      }

      expectLess('0.1.0', '1.0.0');
      expectLess('1.0.0', '1.2.0');
      expectLess('0.3.9', '0.3.11');
    });

    test('checkSupported', () {
      expect(PowerSyncCoreVersion.parse('0.3.10').checkSupported,
          throwsA(isA<SqliteException>()));
      expect(PowerSyncCoreVersion.parse('1.0.0').checkSupported,
          throwsA(isA<SqliteException>()));

      PowerSyncCoreVersion.minimum.checkSupported();
      expect(PowerSyncCoreVersion.maximumExclusive.checkSupported,
          throwsA(isA<SqliteException>()));
    });
  });
}
