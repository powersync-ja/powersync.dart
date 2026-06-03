@TestOn('browser')
library;

import 'dart:async';

import 'package:logging/logging.dart';
import 'package:powersync/powersync.dart';
import 'package:powersync/src/sync/streaming_sync.dart';
import 'package:powersync/src/web/sync_controller.dart';
import 'package:powersync/src/web/sync_worker.dart';
import 'package:test/test.dart';
import 'package:web/web.dart' show MessageChannel;

import '../server/sync_server/in_memory_sync_server.dart';
import '../sync/utils.dart';
import '../utils/abstract_test_utils.dart';
import '../utils/in_memory_http.dart';
import '../utils/web_test_utils.dart';

void main() {
  late final TestUtils utils;
  late SyncWorker syncWorker;
  late PowerSyncDatabase db;

  setUpAll(() async {
    utils = TestUtils();
  });

  setUp(() async {
    syncWorker = SyncWorker();

    db = await utils.setupPowerSync(logger: Logger.detached('test_logger'));
    await db.initialize();
  });

  SyncWorkerHandle createWorkerHandle({
    required PowerSyncBackendConnector connector,
    SyncOptions options = const SyncOptions(),
    List<SubscribedStream> subscriptions = const [],
  }) {
    final rawChannel = MessageChannel();
    syncWorker.trackPort(rawChannel.port1);

    final handle = SyncWorkerHandle(
      database: db,
      connector: connector,
      options: options,
      sendToWorker: rawChannel.port2,
      worker: null,
      subscriptions: subscriptions,
    );
    handle.statusStream.forEach(db.setStatus);
    return handle;
  }

  test('aborts sync when database is closed', () async {
    final handle = createWorkerHandle(connector: _ThrowingBackendConnector());
    final hasError = expectLater(
        db.statusStream,
        emitsThrough(isA<SyncStatus>()
            .having((e) => e.downloadError, 'downloadError', isNotNull)));
    await handle.streamingSync();
    await hasError;

    expect(db.currentStatus.downloadError.toString(),
        contains('Expected error from fetchCredentials'));
    final syncRunner = syncWorker.requestedSyncTasks.values.single;
    expect(syncRunner.sync, isNotNull);
    expect(syncRunner.connections, hasLength(1));

    await handle.closeChannel();
    await pumpEventQueue();

    // This should abort the sync process
    expect(syncRunner.sync, isNull);
    expect(syncRunner.connections, isEmpty);
  });

  test('handles tabs closing while serving a request', () async {
    late SyncWorkerHandle handle;
    final didRequestCredentials = Completer<void>();
    handle = createWorkerHandle(connector: _ThrowingBackendConnector(() {
      // When the fetchCredentials request is sent, there should be a sync
      // process.
      final syncRunner = syncWorker.requestedSyncTasks.values.single;
      expect(syncRunner.sync, isNotNull);
      expect(syncRunner.connections, hasLength(1));

      // Close the handle while the fetchCredentials request is active, meaning
      // the sync worker will never receive a response.
      handle.closeChannel();
      didRequestCredentials.complete();
    }));

    await handle.streamingSync();
    await didRequestCredentials.future;
    await pumpEventQueue();

    final syncRunner = syncWorker.requestedSyncTasks.values.single;
    expect(syncRunner.sync, isNull);
    expect(syncRunner.connections, isEmpty);
  });

  test('can use custom http client', () async {
    final (client, server) = inMemoryServer();
    final service = MockSyncService();
    server.mount((r) => service.router(r));
    service
      ..addLine(checkpoint(lastOpId: 1))
      ..addLine(checkpointComplete());

    final handle = createWorkerHandle(
      connector: TestConnector(
        () async => PowerSyncCredentials(
            endpoint: 'http://test.powersync.example.org', token: 'token'),
      ),
      options: SyncOptions(httpClient: () => client),
    );
    await handle.streamingSync();
    await db.waitForFirstSync();
  });
}

final class _ThrowingBackendConnector extends PowerSyncBackendConnector {
  void Function()? onFetchCredentials;

  _ThrowingBackendConnector([this.onFetchCredentials]);

  @override
  Future<PowerSyncCredentials?> fetchCredentials() async {
    onFetchCredentials?.call();
    throw UnsupportedError('Expected error from fetchCredentials');
  }

  @override
  Future<void> uploadData(PowerSyncDatabase database) async {}
}
