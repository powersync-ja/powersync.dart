import 'package:powersync/powersync.dart';
import 'package:powersync/sqlite3_common.dart';
import 'package:test/test.dart';

import '../utils/test_utils_impl.dart';

void main() {
  late String path;
  late TestUtils testUtils;

  setUpAll(() => testUtils = TestUtils());

  setUp(() async {
    path = testUtils.dbPath();
    await testUtils.cleanDb(path: path);
  });

  test('generates pragma statements', () {
    expect(
      EncryptionOptions(key: 'foo', sqlcipherCompatibility: false)
          .pragmaStatements(),
      ["PRAGMA key = 'foo'"],
    );
    expect(
      EncryptionOptions(key: 'foo', sqlcipherCompatibility: true)
          .pragmaStatements(),
      [
        "PRAGMA cipher = 'sqlcipher'",
        'PRAGMA legacy = 4',
        "PRAGMA key = 'foo'"
      ],
    );

    expect(
      EncryptionOptions(key: "f'o'o", sqlcipherCompatibility: false)
          .pragmaStatements(),
      ["PRAGMA key = 'f''o''o'"],
    );
  });

  group(
    'without encryption',
    () {
      test('throws when encryption options are used', () async {
        await expectLater(() async {
          await testUtils.setupPowerSync(
              encryption: EncryptionOptions(key: 'foo'));
        }, throwsA(anything));
      });
    },
    tags: 'require_no_encryption',
  );

  // To run the following tests, uncomment hook options in the monorepo's
  // pubspec.yaml and run dart test -P encryption.

  group('with encryption', () {
    test('smoke test', () async {
      final path = testUtils.dbPath();

      // First database: Open with encryption key.
      {
        final db = await testUtils.setupPowerSync(
          path: path,
          encryption: EncryptionOptions(key: 'foo'),
        );

        await db.execute('INSERT INTO customers (id, name) VALUES (uuid(), ?)',
            ['secret customer']);
        await db.close();
      }

      // Opening without the key should fail.
      await expectLater(() async {
        await testUtils.setupPowerSync(path: path);
      }, throwsA(isA<SqliteException>()));

      // A different key should fail too.
      await expectLater(() async {
        await testUtils.setupPowerSync(
          path: path,
          encryption: EncryptionOptions(key: 'bar'),
        );
      }, throwsA(isA<SqliteException>()));
    });
  }, tags: 'require_encryption');
}
