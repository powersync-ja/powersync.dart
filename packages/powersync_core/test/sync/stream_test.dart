import 'dart:async';
import 'dart:convert';

import 'package:async/async.dart';
import 'package:logging/logging.dart';
import 'package:powersync_core/powersync_core.dart';

import 'package:test/test.dart';

import '../server/sync_server/in_memory_sync_server.dart';
import '../utils/abstract_test_utils.dart';
import '../utils/in_memory_http.dart';
import '../utils/test_utils_impl.dart';
import 'utils.dart';

void main() {
  late final testUtils = TestUtils();

  late TestPowerSyncFactory factory;

  late TestDatabase database;
  late MockSyncService syncService;
  late Logger logger;
  late SyncOptions options;

  var credentialsCallbackCount = 0;

  Future<void> connect() async {
    final (client, server) = inMemoryServer();
    server.mount(syncService.router.call);

    database.httpClient = client;
    await database.connect(
      connector: TestConnector(
        () async {
          credentialsCallbackCount++;
          return PowerSyncCredentials(
            endpoint: server.url.toString(),
            token: 'token$credentialsCallbackCount',
            expiresAt: DateTime.now(),
          );
        },
        uploadData: (db) async {},
      ),
      options: options,
    );
  }

  setUp(() async {
    options = SyncOptions(syncImplementation: SyncClientImplementation.rust);
    logger = Logger.detached('powersync.active')..level = Level.ALL;
    credentialsCallbackCount = 0;
    syncService = MockSyncService();

    factory = await testUtils.testFactory();
    (_, database) = await factory.openInMemoryDatabase();
    await database.initialize();
  });

  tearDown(() async {
    await database.close();
    await syncService.stop();
  });

  Future<StreamQueue<SyncStatus>> waitForConnection(
      {bool expectNoWarnings = true}) async {
    if (expectNoWarnings) {
      logger.onRecord.listen((e) {
        if (e.level >= Level.WARNING) {
          fail('Unexpected log: $e, ${e.stackTrace}');
        }
      });
    }
    await connect();
    await syncService.waitForListener;

    expect(database.currentStatus.lastSyncedAt, isNull);
    expect(database.currentStatus.downloading, isFalse);
    final status = StreamQueue(database.statusStream);
    addTearDown(status.cancel);

    syncService.addKeepAlive();
    await expectLater(
        status, emitsThrough(isSyncStatus(connected: true, hasSynced: false)));
    return status;
  }

  test('can disable default streams', () async {
    options = SyncOptions(
      syncImplementation: SyncClientImplementation.rust,
      includeDefaultStreams: false,
    );

    await waitForConnection();
    final request = await syncService.waitForListener;
    expect(json.decode(await request.readAsString()),
        containsPair('streams', containsPair('include_defaults', false)));
  });

  test('subscribes with streams', () async {
    final a = await database.syncStream('stream', {'foo': 'a'}).subscribe();
    final b = await database.syncStream('stream', {'foo': 'b'}).subscribe(
        priority: StreamPriority(1));

    final statusStream = await waitForConnection();
    final request = await syncService.waitForListener;
    expect(
      json.decode(await request.readAsString()),
      containsPair(
        'streams',
        containsPair('subscriptions', [
          {
            'stream': 'stream',
            'parameters': {'foo': 'a'},
            'override_priority': null,
          },
          {
            'stream': 'stream',
            'parameters': {'foo': 'b'},
            'override_priority': 1,
          },
        ]),
      ),
    );

    syncService.addLine(
      checkpoint(
        lastOpId: 0,
        buckets: [
          bucketDescription('a', subscriptions: [
            {'sub': 0}
          ]),
          bucketDescription('b', priority: 1, subscriptions: [
            {'sub': 1}
          ])
        ],
        streams: [
          stream('stream', false),
        ],
      ),
    );

    var status = await statusStream.next;
    for (final subscription in [a, b]) {
      expect(status.statusFor(subscription)!.subscription.active, true);
      expect(status.statusFor(subscription)!.subscription.lastSyncedAt, isNull);
      expect(
        status.statusFor(subscription)!.subscription.hasExplicitSubscription,
        true,
      );
    }

    syncService.addLine(checkpointComplete(priority: 1));
    status = await statusStream.next;
    expect(status.statusFor(a)!.subscription.lastSyncedAt, isNull);
    expect(status.statusFor(b)!.subscription.lastSyncedAt, isNotNull);
    await b.waitForFirstSync();

    syncService.addLine(checkpointComplete());
    await a.waitForFirstSync();
  });

  test('reports default streams', () async {
    final status = await waitForConnection();
    syncService.addLine(
      checkpoint(lastOpId: 0, streams: [stream('default_stream', true)]),
    );

    await expectLater(
      status,
      emits(
        isSyncStatus(
          subscriptions: [
            isStreamStatus(
              subscription: isSyncSubscription(
                name: 'default_stream',
                parameters: null,
                isDefault: true,
              ),
            ),
          ],
        ),
      ),
    );
  });

  test('changes subscriptions dynamically', () async {
    await waitForConnection();
    syncService.addKeepAlive();

    final subscription = await database.syncStream('a').subscribe();
    syncService.endCurrentListener();
    final request = await syncService.waitForListener;
    expect(
      json.decode(await request.readAsString()),
      containsPair(
        'streams',
        containsPair('subscriptions', [
          {
            'stream': 'a',
            'parameters': null,
            'override_priority': null,
          },
        ]),
      ),
    );

    // Given that the subscription has a TTL, dropping the handle should not
    // re-subscribe.
    subscription.unsubscribe();
    await pumpEventQueue();
    expect(syncService.controller.hasListener, isTrue);
  });

  test('subscriptions update while offline', () async {
    final stream = StreamQueue(database.statusStream);

    final subscription = await database.syncStream('foo').subscribe();
    var status = await stream.next;
    expect(status.statusFor(subscription), isNotNull);
  });
}
