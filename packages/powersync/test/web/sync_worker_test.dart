@TestOn('browser')
library;

import 'dart:async';
import 'dart:convert';

import 'package:async/async.dart';
import 'package:logging/logging.dart';
import 'package:powersync/powersync.dart';
import 'package:powersync/src/connector.dart';
import 'package:powersync/src/sync/internal_connector.dart';
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

  var dbId = 0;

  setUpAll(() async {
    utils = TestUtils();
  });

  setUp(() async {
    syncWorker = SyncWorker();

    db = await utils.setupPowerSync(
      path: 'sync-worker-test-${dbId++}',
      logger: Logger.detached('test_logger'),
    );
    await db.initialize();
  });

  SyncWorkerHandle createWorkerHandle({
    required InternalConnector connector,
    SyncOptions options = const SyncOptions(),
    List<SubscribedStream> subscriptions = const [],
    bool applyStatusToDatabase = true,
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
    if (applyStatusToDatabase) {
      handle.statusUpdates.forEach(
        (update) => db.setStatus(update.applyTo(db.currentStatus)),
      );
    }
    return handle;
  }

  test('aborts sync when database is closed', () async {
    final handle = createWorkerHandle(
      connector: InternalConnector(
        _CallbackAuthenticator(
          getCredentials: () async {
            throw UnsupportedError('Expected error from fetchCredentials');
          },
        ),
        null,
      ),
    );
    final hasError = expectLater(
      db.statusStream,
      emitsThrough(
        isA<SyncStatus>().having(
          (e) => e.downloadError,
          'downloadError',
          isNotNull,
        ),
      ),
    );
    await handle.streamingSync();
    await hasError;

    expect(
      db.currentStatus.downloadError.toString(),
      contains('Expected error from fetchCredentials'),
    );
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
    handle = createWorkerHandle(
      connector: InternalConnector(
        _CallbackAuthenticator(
          getCredentials: () async {
            // When the fetchCredentials request is sent, there should be a sync
            // process.
            final syncRunner = syncWorker.requestedSyncTasks.values.single;
            expect(syncRunner.sync, isNotNull);
            expect(syncRunner.connections, hasLength(1));

            // Close the handle while the fetchCredentials request is active,
            // meaning the sync worker will never receive a response.
            handle.closeChannel();
            didRequestCredentials.complete();

            throw UnsupportedError('Expected error from fetchCredentials');
          },
        ),
        null,
      ),
    );

    await handle.streamingSync();
    await didRequestCredentials.future;
    await pumpEventQueue();

    final syncRunner = syncWorker.requestedSyncTasks.values.single;
    expect(syncRunner.sync, isNull);
    expect(syncRunner.connections, isEmpty);
  });

  test('reports errors to clients connecting later', () async {
    // Use a long retry delay so that the download error is only reported once.
    const options = SyncOptions(retryDelay: Duration(minutes: 1));
    final first = createWorkerHandle(
      connector: _ThrowingBackendConnector().toInternal(db),
      options: options,
    );
    final statusChanges = StreamQueue(db.statusStream);
    await first.streamingSync();

    await expectLater(
      statusChanges,
      emitsThrough(isSyncStatus(downloadError: isNotNull)),
    );

    // Trigger an upload, emitting status updates that don't change the
    // download error.
    await db.execute(
      "INSERT INTO customers (id, name) VALUES (uuid(), 'name')",
    );
    await expectLater(
      statusChanges,
      emitsThrough(isSyncStatus(uploading: true)),
    );

    // A connecting client should receive the existing download error.
    final second = createWorkerHandle(
      connector: _ThrowingBackendConnector().toInternal(db),
      options: options,
      applyStatusToDatabase: false,
    );
    final initialUpdate = second.statusUpdates.first;
    await second.streamingSync();

    final status = (await initialUpdate).applyTo(
      const SyncStatus.uninitialized(),
    );
    expect(
      status.downloadError.toString(),
      contains('Expected error from fetchCredentials'),
    );

    await statusChanges.cancel();
    await first.abort();
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
          endpoint: 'http://test.powersync.example.org',
          token: 'token',
        ),
      ).toInternal(db),
      options: SyncOptions(httpClient: () => client),
    );
    await handle.streamingSync();
    await db.waitForFirstSync();
  });

  test('can use requests mode', () async {
    final (client, server) = inMemoryServer();
    final service = MockSyncService();
    server.mount((r) => service.router(r));

    final handle = createWorkerHandle(
      connector: TestConnector(
        () async => PowerSyncCredentials(
          endpoint: 'http://test.powersync.example.org',
          token: 'token',
        ),
      ).toInternal(db),
      options: SyncOptions(
        httpClient: () => client,
        checkpointMode: CheckpointMode.requests(),
      ),
    );
    await handle.streamingSync();

    await service.waitForCheckpointRequest(
      () => service.amountOfCheckpointRequests > 0,
    );

    final checkpoint = await handle.requestCheckpoint();
    expect(checkpoint.toString(), '2');
    await handle.abort();
  });

  test('can use custom checkpoint connector', () async {
    final (client, server) = inMemoryServer();
    final service = MockSyncService();
    server.mount((r) => service.router(r));
    final didRequestCheckpoint = Completer<void>();

    final handle = createWorkerHandle(
      connector: InternalConnector(
        _CallbackAuthenticator(
          getCredentials: () async => PowerSyncCredentials(
            endpoint: 'http://test.powersync.example.org',
            token: 'token',
          ),
          postCheckpoints: (clientId, checkpoint) async {
            expect(checkpoint, '1');
            didRequestCheckpoint.complete();
            return checkpoint;
          },
        ),
        null,
      ),
      options: SyncOptions(
        httpClient: () => client,
        checkpointMode: CheckpointMode.requests(),
      ),
    );
    await handle.streamingSync();
    await didRequestCheckpoint.future;
    await handle.abort();
  });

  test('forwards diagnostics events', () async {
    final (client, server) = inMemoryServer();
    final service = MockSyncService();
    server.mount((r) => service.router(r));

    final handle = createWorkerHandle(
      connector: TestConnector(
        () async => PowerSyncCredentials(
          endpoint: 'http://test.powersync.example.org',
          token: 'token',
        ),
      ).toInternal(db),
      options: SyncOptions(httpClient: () => client, enableDiagnostics: true),
    );

    await handle.streamingSync();
    await service.waitForListener;
    final didEmit = expectLater(
      handle.diagnostics.map(json.decode),
      emits({
        'BucketStateChange': {
          // We don't care about the exact diagnostic event, just that one is
          // emitted.
          'changes': [anything],
          'incremental': false,
        },
      }),
    );
    service
      ..addLine(checkpoint(lastOpId: 1, buckets: [bucketDescription('a')]))
      ..addLine({
        'data': {
          'bucket': 'a',
          'data': [
            {
              'checksum': 0,
              'data': json.encode({'name': 'custom list'}),
              'op': 'PUT',
              'op_id': '1',
              'object_id': 'my_list',
              'object_type': 'lists',
            },
          ],
        },
      })
      ..addLine(checkpointComplete(lastOpId: '1'));

    await db.waitForFirstSync();
    await handle.close();
    await didEmit;
  });

  test('refuses connections of different modes', () async {
    final a = createWorkerHandle(
      connector: InternalConnector(
        _CallbackAuthenticator(
          getCredentials: () async => PowerSyncCredentials(
            endpoint: 'http://test.powersync.example.org',
            token: 'token',
          ),
        ),
        null,
      ),
    );
    await a.streamingSync();

    final b = createWorkerHandle(
      connector: InternalConnector(null, _MockUploader(() async {})),
    );
    expect(
      b.streamingSync(),
      throwsA(
        isA<Object>().having(
          (e) => e.toString(),
          'toString()',
          contains('Different tabs connecting in different modes'),
        ),
      ),
    );
  });
}

final class _CallbackAuthenticator implements InternalAuthenticator {
  final Future<PowerSyncCredentials?> Function()? getCredentials;
  final Future<String> Function(String, String)? postCheckpoints;

  _CallbackAuthenticator({required this.getCredentials, this.postCheckpoints});

  @override
  bool get mightPostCheckpointRequests => postCheckpoints != null;

  @override
  Future<PowerSyncCredentials?> getCredentialsCached() async {
    return await getCredentials?.call();
  }

  @override
  FutureOr<String?> postCheckpointRequest(
    String clientId,
    String checkpointRequestId,
  ) {
    return postCheckpoints?.call(clientId, checkpointRequestId);
  }

  @override
  Future<PowerSyncCredentials?> prefetchCredentials({bool invalidate = false}) {
    return getCredentialsCached();
  }
}

final class _MockUploader implements InternalMutationUploader {
  final Future<void> Function() _upload;

  _MockUploader(this._upload);

  @override
  Future<void> upload() => _upload();
}

final class _ThrowingBackendConnector extends PowerSyncBackendConnector {
  _ThrowingBackendConnector();

  @override
  Future<PowerSyncCredentials?> fetchCredentials() async {
    throw UnsupportedError('Expected error from fetchCredentials');
  }

  @override
  Future<void> uploadData(PowerSyncDatabase database) async {}
}
