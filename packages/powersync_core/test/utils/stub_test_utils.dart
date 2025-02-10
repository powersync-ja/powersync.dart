import 'package:sqlite_async/src/sqlite_options.dart';

import 'abstract_test_utils.dart';

class TestUtils extends AbstractTestUtils {
  @override
  Future<TestPowerSyncFactory> testFactory(
      {String? path,
      String sqlitePath = '',
      SqliteOptions options = const SqliteOptions.defaults()}) {
    throw UnimplementedError();
  }

  @override
  Future<void> cleanDb({required String path}) {
    throw UnimplementedError();
  }
}
