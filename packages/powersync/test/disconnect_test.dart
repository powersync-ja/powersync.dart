import 'dart:async';

import 'package:powersync/powersync.dart';
import 'package:sqlite_async/sqlite_async.dart';
import 'package:test/test.dart';
import 'utils/abstract_test_utils.dart';
import 'utils/test_utils_impl.dart';
import 'watch_test.dart';

final testUtils = TestUtils();

void main() {
  group('Disconnect Tests', () {
    late String path;

    setUp(() async {
      path = testUtils.dbPath();
      await testUtils.cleanDb(path: path);
    });

    test('Multiple calls to disconnect', () async {
      final db = await testUtils.setupPowerSync(path: path, schema: testSchema);

      credentialsCallback() async {
        // A blank endpoint will fail, but that's okay for this test
        final endpoint = '';
        return PowerSyncCredentials(
          endpoint: endpoint,
          token: 'token',
          userId: 'u1',
          expiresAt: DateTime.now(),
        );
      }

      // ignore: deprecated_member_use_from_same_package
      db.retryDelay = Duration(milliseconds: 5000);
      var connector = TestConnector(credentialsCallback);
      await db.connect(connector: connector);

      // Call disconnect multiple times, each Future should resolve
      final disconnect1 = db.disconnect();
      final disconnect2 = db.disconnect();

      await expectLater(disconnect1, completes);
      await expectLater(disconnect2, completes);
    });

    test('aborts pending connector calls on disconnect', () async {
      final db = await testUtils.setupPowerSync(path: path, schema: testSchema);
      final didRequestCredentials = Completer<void>();
      final didAbort = Completer<void>();

      await db.connect(
        connector: ConnectRequest.downloadOnly(
          endpoint: 'http://localhost:1',
          authenticator: _CallbackAuthenticator((abortSignal) async {
            didRequestCredentials.complete();
            await abortSignal;
            didAbort.complete();
            throw StateError('aborted');
          }),
        ),
      );

      await didRequestCredentials.future;
      await db.disconnect();
      expect(didAbort.isCompleted, isTrue);
    });

    test('completes abort signal after connector call', () async {
      final db = await testUtils.setupPowerSync(path: path, schema: testSchema);
      final abortSignal = Completer<Future<void>>();

      await db.connect(
        connector: ConnectRequest.downloadOnly(
          endpoint: 'http://localhost:1',
          authenticator: _CallbackAuthenticator((signal) async {
            if (!abortSignal.isCompleted) abortSignal.complete(signal);
            return 'token';
          }),
        ),
      );

      await (await abortSignal.future);
      await db.disconnect();
    });

    test('disconnectAndClear clears DB', () async {
      final db = await testUtils.setupPowerSync(path: path, schema: testSchema);

      await db.execute(
        'INSERT INTO customers (id, name, email) VALUES(uuid(), ?, ?)',
        ['Steven', 'steven@journeyapps.com'],
      );

      final getCustomersQuery = 'SELECT * from customers';
      final initialCustomers = await db.getAll(getCustomersQuery);
      expect(initialCustomers.length, equals(1));

      final changesFuture = db
          .onChange({'customers'}, triggerImmediately: false)
          .take(1)
          .toList();

      await db.disconnectAndClear();

      final finalCustomers = await db.getAll(getCustomersQuery);
      expect(finalCustomers.length, equals(0));

      expect(db.currentStatus.lastSyncedAt, equals(null));
      expect(db.currentStatus.hasSynced, equals(false));

      final changes = await changesFuture;
      expect(changes.first, equals(UpdateNotification({'customers'})));
    });

    test('soft clear', () async {
      final db = await testUtils.setupPowerSync(path: path, schema: testSchema);
      await db.execute(
        'INSERT INTO customers (id, name, email) VALUES(uuid(), ?, ?)',
        ['Testing', 'testing@powersync.com'],
      );
      await db.execute(
        'INSERT INTO ps_buckets (name, last_applied_op) VALUES (?, ?)',
        ['bkt', 10],
      );

      // Doing a soft-clear should delete data but keep the bucket around.
      await db.disconnectAndClear(soft: true);
      expect(await db.get('SELECT name FROM ps_buckets'), {'name': 'bkt'});

      // Doing a default clear also deletes buckets.
      await db.disconnectAndClear();
      expect(await db.getAll('SELECT name FROM ps_buckets'), isEmpty);
    });
  });
}

final class _CallbackAuthenticator implements Authenticator {
  final Future<String> Function(Future<void> abortSignal) _resolve;

  _CallbackAuthenticator(this._resolve);

  @override
  Future<String> resolveCredentials(Future<void> abortSignal) {
    return _resolve(abortSignal);
  }

  @override
  void invalidateCredentials() {}
}
