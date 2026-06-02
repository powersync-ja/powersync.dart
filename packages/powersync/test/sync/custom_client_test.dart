import 'package:http/http.dart';
import 'package:powersync/powersync.dart';
import 'package:test/test.dart';

import '../server/sync_server/in_memory_sync_server.dart';
import '../utils/abstract_test_utils.dart';
import '../utils/in_memory_http.dart';
import '../utils/test_utils_impl.dart';
import 'utils.dart';

void main() {
  late PowerSyncDatabase powersync;
  late String path;

  setUp(() async {
    path = _testUtils.dbPath();
    await _testUtils.cleanDb(path: path);

    powersync = await _testUtils.setupPowerSync(path: path);
  });

  tearDown(() => powersync.close());

  test('can use custom http client', () async {
    await powersync.connect(
      connector: TestConnector(
        () async => PowerSyncCredentials(
            endpoint: 'http://test.powersync.example.org', token: 'token'),
      ),
      options: SyncOptions(
        httpClient: _createMockClient,
      ),
    );

    await powersync.waitForFirstSync();
  });
}

Client _createMockClient() {
  final (client, server) = inMemoryServer();
  final service = MockSyncService();
  server.mount((r) => service.router(r));

  service
    ..addLine(checkpoint(lastOpId: 1))
    ..addLine(checkpointComplete());
  return client;
}

final _testUtils = TestUtils();
