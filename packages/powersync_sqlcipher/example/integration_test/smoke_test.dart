import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'package:powersync_sqlcipher/powersync.dart';
import 'package:powersync_sqlcipher/sqlite3_common.dart';
import 'package:powersync_sqlcipher/sqlite_async.dart';

void main() {
  test('can use encrypted database', () async {
    var path = 'powersync-demo.db';
    // getApplicationSupportDirectory is not supported on Web
    if (!kIsWeb) {
      final dir = await getApplicationSupportDirectory();
      path = join(dir.path, 'powersync-dart.db');
    }

    var db = PowerSyncDatabase.withFactory(
      PowerSyncSQLCipherOpenFactory(path: path, key: 'demo-key'),
      schema: schema,
    );

    await db.execute('INSERT INTO users (id, name) VALUES (uuid(), ?)', [
      'My username',
    ]);
    await db.close();

    expect(() async {
      db = PowerSyncDatabase.withFactory(
        PowerSyncSQLCipherOpenFactory(path: path, key: 'changed-key'),
        schema: schema,
      );

      await db.initialize();
    }, throwsA(anything));
  });

  if (!kIsWeb) {
    test('can register user-defined function', () async {
      final path = join(
        (await getApplicationSupportDirectory()).path,
        'powersync-demo.db',
      );

      final db = PowerSyncDatabase.withFactory(
        _CustomOpenFactory(path: path, key: 'demo-key'),
        schema: schema,
      );

      await db.get('SELECT my_function()');
    });
  }
}

final schema = Schema([
  Table('users', [Column.text('name')]),
]);

final class _CustomOpenFactory extends PowerSyncSQLCipherOpenFactory {
  _CustomOpenFactory({required super.path, required super.key});

  @override
  CommonDatabase open(SqliteOpenOptions options) {
    final db = super.open(options);
    db.createFunction(
      functionName: 'my_function',
      function: (_) => 123,
      argumentCount: AllowedArgumentCount.any(),
    );
    return db;
  }
}
