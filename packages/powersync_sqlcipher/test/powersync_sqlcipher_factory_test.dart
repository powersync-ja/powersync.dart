import 'package:powersync_core/powersync_core.dart';
import 'package:flutter_test/flutter_test.dart';

import 'utils/test_utils.dart';

final testUtils = TestUtils();

void main() {
  group('SQLCipher Tests', () {
    late String path;

    setUp(() async {
      path = testUtils.dbPath();
      await testUtils.cleanDb(path: path);
    });

    test('PRAGMA cipher_version returns version', () async {
      final cipherFactory =
          await testUtils.testFactory(path: path, key: "test-key");

      final db = PowerSyncDatabase.withFactory(cipherFactory, schema: schema);

      await db.initialize();

      final row = await db.get('PRAGMA cipher_version');
      expect(row, isNotNull);
      expect(row['cipher_version'], equals('4.6.1 community'));
    });
  });
}
