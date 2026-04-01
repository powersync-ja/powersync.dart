import 'package:sqlite3/src/database.dart';
import 'package:sqlite_async/sqlite_async.dart';

import 'abstract_test_utils.dart';

class TestUtils extends AbstractTestUtils {
  @override
  Future<SqliteOpenFactory> testFactory(
      {String? path,
      String sqlitePath = '',
      SqliteOptions options = const SqliteOptions()}) {
    throw UnimplementedError();
  }

  @override
  Future<void> cleanDb({required String path}) {
    throw UnimplementedError();
  }

  @override
  Future<CommonDatabase> openRawInMemoryDatabase() {
    throw UnimplementedError();
  }
}
