import 'package:logging/logging.dart';
import 'package:powersync/powersync.dart';
import 'package:test/test.dart';

import 'test_server.dart';
import 'utils/abstract_test_utils.dart';
import 'utils/test_utils_impl.dart';

final testUtils = TestUtils();
const testId = "2290de4f-0488-4e50-abed-f8e8eb1d0b42";
const testId2 = "2290de4f-0488-4e50-abed-f8e8eb1d0b43";
const partialWarning =
    'Potentially previously uploaded CRUD entries are still present';

class TestConnector extends PowerSyncBackendConnector {
  final Function _fetchCredentials;
  final Future<void> Function(PowerSyncDatabase database) _uploadData;

  TestConnector(this._fetchCredentials, this._uploadData);

  @override
  Future<PowerSyncCredentials?> fetchCredentials() {
    return _fetchCredentials();
  }

  @override
  Future<void> uploadData(PowerSyncDatabase database) async {
    return _uploadData(database);
  }
}

void main() {
  group('CRUD Tests', () {
    late PowerSyncDatabase powersync;
    late String path;

    setUp(() async {
      path = testUtils.dbPath();
      await testUtils.cleanDb(path: path);
    });

    tearDown(() async {
      // await powersync.disconnectAndClear();
      await powersync.close();
    });

    test('should warn for missing upload operations in uploadData', () async {
      var server = await createServer();

      credentialsCallback() async {
        return PowerSyncCredentials(
          endpoint: server.endpoint,
          token: 'token',
          userId: 'userId',
        );
      }

      uploadData(PowerSyncDatabase db) async {
        // Do nothing
      }

      final records = <LogRecord>[];
      final sub = testWarningLogger.onRecord.listen(records.add);

      powersync =
          await testUtils.setupPowerSync(path: path, logger: testWarningLogger);
      powersync.retryDelay = Duration(milliseconds: 0);
      var connector = TestConnector(credentialsCallback, uploadData);
      powersync.connect(connector: connector);

      // Create something with CRUD in it.
      await powersync.execute(
          'INSERT INTO assets(id, description) VALUES(?, ?)', [testId, 'test']);

      // Wait for the uploadData to be called.
      await Future.delayed(Duration(milliseconds: 100));

      // Create something else with CRUD in it.
      await powersync.execute(
          'INSERT INTO assets(id, description) VALUES(?, ?)',
          [testId2, 'test2']);

      sub.cancel();

      var warningLogs = records.where((r) => r.level == Level.WARNING).toList();
      expect(warningLogs, hasLength(2));
      expect(warningLogs[0].message, contains(partialWarning));
    });
  });
}
