import 'dart:async';
import 'dart:convert';

import 'package:async/async.dart';
import 'package:logging/logging.dart';
import 'package:powersync_core/powersync_core.dart';
import 'package:powersync_core/sqlite3_common.dart';
import 'package:powersync_core/src/sync/streaming_sync.dart';
import 'package:powersync_core/src/sync/protocol.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';
import 'package:test/test.dart';

import 'bucket_storage_test.dart';
import 'server/sync_server/in_memory_sync_server.dart';
import 'utils/abstract_test_utils.dart';
import 'utils/in_memory_http.dart';
import 'utils/test_utils_impl.dart';

void main() {
  _declareTests(
    'dart sync client',
    SyncOptions(
      // ignore: deprecated_member_use_from_same_package
      syncImplementation: SyncClientImplementation.dart,
      retryDelay: Duration(milliseconds: 200),
    ),
    false,
  );

  group('rust sync client', () {
    _declareTests(
      'json',
      SyncOptions(
          syncImplementation: SyncClientImplementation.rust,
          retryDelay: Duration(milliseconds: 200)),
      false,
    );

    _declareTests(
      'bson',
      SyncOptions(
          syncImplementation: SyncClientImplementation.rust,
          retryDelay: Duration(milliseconds: 200)),
      true,
    );
  });
}

void _declareTests(String name, SyncOptions options, bool bson) {
  final ignoredLogger = Logger.detached('powersync.test')..level = Level.OFF;

  group(name, () {
    late final testUtils = TestUtils();

    late TestPowerSyncFactory factory;
    late CommonDatabase raw;
    late PowerSyncDatabase database;
    late MockSyncService syncService;
    late Logger logger;

    late StreamingSync syncClient;
    var credentialsCallbackCount = 0;
    Future<void> Function(PowerSyncDatabase) uploadData = (db) async {};

    void createSyncClient({Schema? schema}) {
      final (client, server) = inMemoryServer();
      server.mount((req) => syncService.router(req));

      final thisSyncClient = syncClient = database.connectWithMockService(
        client,
        TestConnector(() async {
          credentialsCallbackCount++;
          return PowerSyncCredentials(
            endpoint: server.url.toString(),
            token: 'token$credentialsCallbackCount',
            expiresAt: DateTime.now(),
          );
        }, uploadData: (db) => uploadData(db)),
        options: options,
        customSchema: schema,
      );

      addTearDown(() async {
        await thisSyncClient.abort();
      });
    }

    setUp(() async {
      logger = Logger.detached('powersync.active')..level = Level.ALL;
      credentialsCallbackCount = 0;
      syncService = MockSyncService(useBson: bson);

      factory = await testUtils.testFactory();
      (raw, database) = await factory.openInMemoryDatabase();
      await database.initialize();
      createSyncClient();
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
      syncClient.streamingSync();
      await syncService.waitForListener;

      expect(database.currentStatus.lastSyncedAt, isNull);
      expect(database.currentStatus.downloading, isFalse);
      final status = StreamQueue(database.statusStream);
      addTearDown(status.cancel);

      syncService.addKeepAlive();
      await expectLater(status,
          emitsThrough(isSyncStatus(connected: true, hasSynced: false)));
      return status;
    }

    test('persists completed sync information', () async {
      final status = await waitForConnection();

      syncService.addLine({
        'checkpoint': {
          'last_op_id': '0',
          'buckets': [
            {
              'bucket': 'bkt',
              'checksum': 0,
            }
          ],
        },
      });
      await expectLater(status, emits(isSyncStatus(downloading: true)));

      syncService.addLine({
        'checkpoint_complete': {'last_op_id': '0'}
      });
      await expectLater(
          status, emits(isSyncStatus(downloading: false, hasSynced: true)));
      await syncClient.abort();

      final independentDb = factory.wrapRaw(raw, logger: ignoredLogger);
      addTearDown(independentDb.close);
      // Even though this database doesn't have a sync client attached to it,
      // is should reconstruct hasSynced from the database.
      await independentDb.initialize();
      expect(independentDb.currentStatus.hasSynced, isTrue);
      // A complete sync also means that all partial syncs have completed
      expect(
          independentDb.currentStatus
              .statusForPriority(BucketPriority(3))
              .hasSynced,
          isTrue);
    });

    // ignore: deprecated_member_use_from_same_package
    if (options.syncImplementation == SyncClientImplementation.dart) {
      test('can save independent buckets in same transaction', () async {
        final status = await waitForConnection();

        syncService.addLine({
          'checkpoint': Checkpoint(
            lastOpId: '0',
            writeCheckpoint: null,
            checksums: [
              BucketChecksum(bucket: 'a', checksum: 0, priority: 3),
              BucketChecksum(bucket: 'b', checksum: 0, priority: 3),
            ],
          )
        });
        await expectLater(status, emits(isSyncStatus(downloading: true)));

        var commits = 0;
        raw.commits.listen((_) => commits++);

        syncService
          ..addLine({
            'data': {
              'bucket': 'a',
              'data': <Map<String, Object?>>[
                {
                  'op_id': '1',
                  'op': 'PUT',
                  'object_type': 'a',
                  'object_id': '1',
                  'checksum': 0,
                  'data': '{}',
                }
              ],
            }
          })
          ..addLine({
            'data': {
              'bucket': 'b',
              'data': <Map<String, Object?>>[
                {
                  'op_id': '2',
                  'op': 'PUT',
                  'object_type': 'b',
                  'object_id': '1',
                  'checksum': 0,
                  'data': '{}',
                }
              ],
            }
          });

        // Wait for the operations to be inserted.
        while (raw.select('SELECT * FROM ps_oplog;').length < 2) {
          await pumpEventQueue();
        }

        // The two buckets should have been inserted in a single transaction
        // because the messages were received in quick succession.
        expect(commits, 1);
      });
    } else {
      // raw tables are only supported by the rust sync client
      test('raw tables', () async {
        final schema = Schema(const [], rawTables: [
          RawTable(
            name: 'lists',
            put: PendingStatement(
              sql: 'INSERT OR REPLACE INTO lists (id, name) VALUES (?, ?)',
              params: [
                PendingStatementValue.id(),
                PendingStatementValue.column('name'),
              ],
            ),
            delete: PendingStatement(
              sql: 'DELETE FROM lists WHERE id = ?',
              params: [
                PendingStatementValue.id(),
              ],
            ),
          ),
        ]);

        await database.execute(
            'CREATE TABLE lists (id TEXT NOT NULL PRIMARY KEY, name TEXT);');
        final query = StreamQueue(
            database.watch('SELECT * FROM lists', throttle: Duration.zero));
        await expectLater(query, emits(isEmpty));

        createSyncClient(schema: schema);
        await waitForConnection();

        syncService
          ..addLine({
            'checkpoint': Checkpoint(
              lastOpId: '1',
              writeCheckpoint: null,
              checksums: [
                BucketChecksum(bucket: 'a', priority: 3, checksum: 0)
              ],
            )
          })
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
                  'object_type': 'lists'
                }
              ]
            }
          })
          ..addLine({
            'checkpoint_complete': {'last_op_id': '1'}
          });

        await expectLater(
          query,
          emits([
            {'id': 'my_list', 'name': 'custom list'}
          ]),
        );

        syncService
          ..addLine({
            'checkpoint': Checkpoint(
              lastOpId: '2',
              writeCheckpoint: null,
              checksums: [
                BucketChecksum(bucket: 'a', priority: 3, checksum: 0)
              ],
            )
          })
          ..addLine({
            'data': {
              'bucket': 'a',
              'data': [
                {
                  'checksum': 0,
                  'op': 'REMOVE',
                  'op_id': '2',
                  'object_id': 'my_list',
                  'object_type': 'lists'
                }
              ]
            }
          })
          ..addLine({
            'checkpoint_complete': {'last_op_id': '2'}
          });

        await expectLater(query, emits(isEmpty));
      });
    }

    group('partial sync', () {
      test('updates sync state incrementally', () async {
        final status = await waitForConnection();

        final checksums = [
          for (var prio = 0; prio <= 3; prio++)
            BucketChecksum(
                bucket: 'prio$prio', priority: prio, checksum: 10 + prio)
        ];
        syncService.addLine({
          'checkpoint': Checkpoint(
            lastOpId: '4',
            writeCheckpoint: null,
            checksums: checksums,
          )
        });
        var operationId = 1;

        void addRow(int priority) {
          syncService.addLine({
            'data': {
              'bucket': 'prio$priority',
              'data': [
                {
                  'checksum': priority + 10,
                  'data': json.encode({'name': 'test', 'email': 'email'}),
                  'op': 'PUT',
                  'op_id': '${operationId++}',
                  'object_id': 'prio$priority',
                  'object_type': 'customers'
                }
              ]
            }
          });
        }

        // Receiving the checkpoint sets the state to downloading
        await expectLater(
            status, emits(isSyncStatus(downloading: true, hasSynced: false)));

        // Emit partial sync complete for each priority but the last.
        for (var prio = 0; prio < 3; prio++) {
          addRow(prio);
          syncService.addLine({
            'partial_checkpoint_complete': {
              'last_op_id': operationId.toString(),
              'priority': prio,
            }
          });

          await expectLater(
            status,
            emitsThrough(
                isSyncStatus(downloading: true, hasSynced: false).having(
              (e) => e.statusForPriority(BucketPriority(0)).hasSynced,
              'status for $prio',
              isTrue,
            )),
          );

          await database.waitForFirstSync(priority: BucketPriority(prio));
          expect(await database.getAll('SELECT * FROM customers'),
              hasLength(prio + 1));
        }

        // Complete the sync
        addRow(3);
        syncService.addLine({
          'checkpoint_complete': {'last_op_id': operationId.toString()}
        });

        await expectLater(status,
            emitsThrough(isSyncStatus(downloading: false, hasSynced: true)));
        await database.waitForFirstSync();
        expect(await database.getAll('SELECT * FROM customers'), hasLength(4));
      });

      test('remembers last partial sync state', () async {
        final status = await waitForConnection();

        syncService.addLine({
          'checkpoint': Checkpoint(
            lastOpId: '0',
            writeCheckpoint: null,
            checksums: [
              BucketChecksum(bucket: 'bkt', priority: 1, checksum: 0)
            ],
          )
        });
        await expectLater(status, emits(isSyncStatus(downloading: true)));

        syncService.addLine({
          'partial_checkpoint_complete': {
            'last_op_id': '0',
            'priority': 1,
          }
        });
        await database.waitForFirstSync(priority: BucketPriority(1));
        expect(database.currentStatus.hasSynced, isFalse);
        await syncClient.abort();

        final independentDb = factory.wrapRaw(raw, logger: ignoredLogger);
        addTearDown(independentDb.close);
        await independentDb.initialize();
        expect(independentDb.currentStatus.hasSynced, isFalse);
        // Completing a sync for prio 1 implies a completed sync for prio 0
        expect(
            independentDb.currentStatus
                .statusForPriority(BucketPriority(0))
                .hasSynced,
            isTrue);
        expect(
            independentDb.currentStatus
                .statusForPriority(BucketPriority(3))
                .hasSynced,
            isFalse);
      });

      test(
        "multiple completed syncs don't create multiple sync state entries",
        () async {
          final status = await waitForConnection();

          for (var i = 0; i < 5; i++) {
            syncService.addLine({
              'checkpoint': Checkpoint(
                lastOpId: '0',
                writeCheckpoint: null,
                checksums: [
                  BucketChecksum(bucket: 'bkt', priority: 1, checksum: 0)
                ],
              )
            });
            await expectLater(status, emits(isSyncStatus(downloading: true)));

            syncService.addLine({
              'checkpoint_complete': {
                'last_op_id': '0',
              }
            });

            await expectLater(status, emits(isSyncStatus(downloading: false)));
          }

          final rows = await database.getAll('SELECT * FROM ps_sync_state;');
          expect(rows, hasLength(1));
        },
      );
    });

    test('reconnects when token expires', () async {
      await waitForConnection();
      expect(credentialsCallbackCount, 1);
      // When the sync service says the token has expired
      syncService
        ..addLine({'token_expires_in': 0})
        ..endCurrentListener();

      final nextRequest = await syncService.waitForListener;
      expect(nextRequest.headers['Authorization'], 'Token token2');
      expect(credentialsCallbackCount, 2);
    });

    test('handles checkpoints during the upload process', () async {
      final status = await waitForConnection();

      Future<void> expectCustomerRows(dynamic matcher) async {
        final rows = await database.getAll('SELECT * FROM customers');
        expect(rows, matcher);
      }

      final uploadStarted = Completer<void>();
      final uploadFinished = Completer<void>();

      uploadData = (db) async {
        if (await db.getCrudBatch() case final batch?) {
          uploadStarted.complete();
          await uploadFinished.future;
          batch.complete();
        }
      };

      // Trigger an upload
      await database.execute(
          'INSERT INTO customers (id, name, email) VALUES (uuid(), ?, ?)',
          ['local', 'local@example.org']);
      await expectCustomerRows(hasLength(1));
      await uploadStarted.future;

      // Pretend that the connector takes forever in uploadData, but the data
      // gets uploaded before the method returns.
      syncService.addLine({
        'checkpoint': Checkpoint(
          writeCheckpoint: '1',
          lastOpId: '2',
          checksums: [BucketChecksum(bucket: 'a', priority: 3, checksum: 0)],
        )
      });
      await expectLater(status, emitsThrough(isSyncStatus(downloading: true)));

      syncService
        ..addLine({
          'data': {
            'bucket': 'a',
            'data': [
              {
                'checksum': 0,
                'data': json.encode(
                    {'name': 'from local', 'email': 'local@example.org'}),
                'op': 'PUT',
                'op_id': '1',
                'object_id': '1',
                'object_type': 'customers'
              },
              {
                'checksum': 0,
                'data': json.encode({'name': 'additional', 'email': ''}),
                'op': 'PUT',
                'op_id': '2',
                'object_id': '2',
                'object_type': 'customers'
              }
            ]
          }
        })
        ..addLine({
          'checkpoint_complete': {'last_op_id': '2'}
        });

      // Despite receiving a valid checkpoint with two rows, it should not be
      // visible because we have local data pending.
      await expectCustomerRows(hasLength(1));

      // Mark the upload as completed, this should trigger a write_checkpoint
      // request.
      final sentCheckpoint = Completer<void>();
      syncService.writeCheckpoint = () {
        sentCheckpoint.complete();
        return {
          'data': {'write_checkpoint': '1'}
        };
      };
      uploadFinished.complete();
      await sentCheckpoint.future;

      // This should apply the checkpoint.
      await expectLater(status, emitsThrough(isSyncStatus(downloading: false)));

      // Meaning that the two rows are now visible.
      await expectCustomerRows(hasLength(2));
    });

    group('reports progress', () {
      var lastOpId = 0;

      setUp(() => lastOpId = 0);

      BucketChecksum bucket(String name, int count, {int priority = 3}) {
        return BucketChecksum(
            bucket: name, priority: priority, checksum: 0, count: count);
      }

      void addDataLine(String bucket, int amount) {
        syncService.addLine({
          'data': {
            'bucket': bucket,
            'data': <Map<String, Object?>>[
              for (var i = 0; i < amount; i++)
                {
                  'op_id': '${++lastOpId}',
                  'op': 'PUT',
                  'object_type': bucket,
                  'object_id': '$lastOpId',
                  'checksum': 0,
                  'data': '{}',
                }
            ],
          }
        });
      }

      void addCheckpointComplete([int? priority]) {
        if (priority case final partial?) {
          syncService.addLine({
            'partial_checkpoint_complete': {
              'last_op_id': '$lastOpId',
              'priority': partial,
            }
          });
        } else {
          syncService.addLine({
            'checkpoint_complete': {
              'last_op_id': '$lastOpId',
            }
          });
        }
      }

      Future<void> expectProgress(
        StreamQueue<SyncStatus> status, {
        required Object total,
        Map<BucketPriority, Object> priorities = const {},
      }) async {
        await expectLater(
          status,
          emitsThrough(isSyncStatus(
            downloading: true,
            downloadProgress: isSyncDownloadProgress(
              progress: total,
              priorities: priorities,
            ),
          )),
        );
      }

      test('without priorities', () async {
        final status = await waitForConnection();
        syncService.addLine({
          'checkpoint': Checkpoint(
            lastOpId: '10',
            checksums: [bucket('a', 10)],
          )
        });
        await expectProgress(status, total: progress(0, 10));

        addDataLine('a', 10);
        await expectProgress(status, total: progress(10, 10));

        addCheckpointComplete();
        await expectLater(status,
            emits(isSyncStatus(downloading: false, downloadProgress: isNull)));

        // Emit new data, progress should be 0/2 instead of 10/12
        syncService.addLine({
          'checkpoint_diff': {
            'last_op_id': '12',
            'updated_buckets': [bucket('a', 12)],
            'removed_buckets': const <Object?>[],
          },
        });
        await expectProgress(status, total: progress(0, 2));
        addDataLine('a', 2);
        await expectProgress(status, total: progress(2, 2));
        addCheckpointComplete();
        await expectLater(status,
            emits(isSyncStatus(downloading: false, downloadProgress: isNull)));
      });

      test('interrupted sync', () async {
        var status = await waitForConnection();
        syncService.addLine({
          'checkpoint': Checkpoint(
            lastOpId: '10',
            checksums: [bucket('a', 10)],
          )
        });
        await expectProgress(status, total: progress(0, 10));
        addDataLine('a', 5);
        await expectProgress(status, total: progress(5, 10));

        // Emulate the app closing - create a new independent sync client.
        await syncClient.abort();
        syncService.endCurrentListener();

        createSyncClient();
        status = await waitForConnection();

        // Send same checkpoint again
        syncService.addLine({
          'checkpoint': Checkpoint(
            lastOpId: '10',
            checksums: [bucket('a', 10)],
          )
        });

        // Progress should be restored instead of saying e.g 0/5 now.
        await expectProgress(status, total: progress(5, 10));
        addCheckpointComplete();
        await expectLater(status,
            emits(isSyncStatus(downloading: false, downloadProgress: isNull)));
      });

      test('interrupted sync with new checkpoint', () async {
        var status = await waitForConnection();
        syncService.addLine({
          'checkpoint': Checkpoint(
            lastOpId: '10',
            checksums: [bucket('a', 10)],
          )
        });
        await expectProgress(status, total: progress(0, 10));
        addDataLine('a', 5);
        await expectProgress(status, total: progress(5, 10));

        // Emulate the app closing - create a new independent sync client.
        await syncClient.abort();
        syncService.endCurrentListener();

        createSyncClient();
        status = await waitForConnection();

        // Send checkpoint with additional data
        syncService.addLine({
          'checkpoint': Checkpoint(
            lastOpId: '12',
            checksums: [bucket('a', 12)],
          )
        });

        await expectProgress(status, total: progress(5, 12));
        addCheckpointComplete();
        await expectLater(status,
            emits(isSyncStatus(downloading: false, downloadProgress: isNull)));
      });

      test('interrupt and defrag', () async {
        var status = await waitForConnection();
        syncService.addLine({
          'checkpoint': Checkpoint(
            lastOpId: '10',
            checksums: [bucket('a', 10)],
          )
        });
        await expectProgress(status, total: progress(0, 10));
        addDataLine('a', 5);
        await expectProgress(status, total: progress(5, 10));

        // A sync rule deploy could reset buckets, making the new bucket smaller
        // than the existing one.
        await syncClient.abort();
        syncService.endCurrentListener();
        createSyncClient();
        status = await waitForConnection();
        syncService.addLine({
          'checkpoint': Checkpoint(
            lastOpId: '14',
            checksums: [bucket('a', 4)],
          )
        });

        // In this special case, don't report 5/4 as progress
        await expectProgress(status, total: progress(0, 4));
      });

      test('different priorities', () async {
        var status = await waitForConnection();
        Future<void> checkProgress(Object prio0, Object prio2) async {
          await expectProgress(
            status,
            priorities: {
              BucketPriority(0): prio0,
              BucketPriority(2): prio2,
            },
            total: prio2,
          );
        }

        syncService.addLine({
          'checkpoint': Checkpoint(
            lastOpId: '10',
            checksums: [
              bucket('a', 5, priority: 0),
              bucket('b', 5, priority: 2)
            ],
          ),
        });
        await checkProgress(progress(0, 5), progress(0, 10));

        addDataLine('a', 5);
        await checkProgress(progress(5, 5), progress(5, 10));

        addCheckpointComplete(0);
        await checkProgress(progress(5, 5), progress(5, 10));

        addDataLine('b', 2);
        await checkProgress(progress(5, 5), progress(7, 10));

        // Before syncing b fully, send a new checkpoint
        syncService.addLine({
          'checkpoint': Checkpoint(
            lastOpId: '14',
            checksums: [
              bucket('a', 8, priority: 0),
              bucket('b', 6, priority: 2)
            ],
          ),
        });
        await checkProgress(progress(5, 8), progress(7, 14));

        addDataLine('a', 3);
        await checkProgress(progress(8, 8), progress(10, 14));

        addCheckpointComplete(0);

        addDataLine('b', 4);
        await checkProgress(progress(8, 8), progress(14, 14));

        addCheckpointComplete();
        await expectLater(status,
            emits(isSyncStatus(downloading: false, downloadProgress: isNull)));
      });
    });

    test('stopping closes connections', () async {
      final status = await waitForConnection();

      syncService.addLine({
        'checkpoint': Checkpoint(
          lastOpId: '4',
          writeCheckpoint: null,
          checksums: [checksum(bucket: 'a', checksum: 0)],
        )
      });

      await expectLater(status, emits(isSyncStatus(downloading: true)));
      await syncClient.abort();

      expect(syncService.controller.hasListener, isFalse);
    });

    test('closes connection after failed checksum', () async {
      final status = await waitForConnection(expectNoWarnings: false);
      syncService.addLine({
        'checkpoint': Checkpoint(
          lastOpId: '4',
          writeCheckpoint: null,
          checksums: [checksum(bucket: 'a', checksum: 10)],
        )
      });

      await expectLater(status, emits(isSyncStatus(downloading: true)));
      syncService.addLine({
        'checkpoint_complete': {'last_op_id': '10'}
      });

      await pumpEventQueue();
      expect(syncService.controller.hasListener, isFalse);
      syncService.endCurrentListener();

      // Should reconnect after delay.
      await Future<void>.delayed(const Duration(milliseconds: 500));
      expect(syncService.controller.hasListener, isTrue);
    });

    test('closes connection after token expires', () async {
      final status = await waitForConnection(expectNoWarnings: false);
      syncService.addLine({
        'checkpoint': Checkpoint(
          lastOpId: '4',
          writeCheckpoint: null,
          checksums: [checksum(bucket: 'a', checksum: 10)],
        )
      });

      await expectLater(status, emits(isSyncStatus(downloading: true)));
      syncService.addKeepAlive(0);

      await pumpEventQueue();
      expect(syncService.controller.hasListener, isFalse);
      syncService.endCurrentListener();

      // Should reconnect after delay.
      await Future<void>.delayed(const Duration(milliseconds: 500));
      expect(syncService.controller.hasListener, isTrue);
    });

    test('uploads writes made while offline', () async {
      // Local write while not connected
      await database.execute(
          'insert into customers (id, name) values (uuid(), ?)',
          ['local customer']);
      uploadData = (db) async {
        final batch = await db.getNextCrudTransaction();
        if (batch != null) {
          await batch.complete();
        }
      };
      syncService.writeCheckpoint = () => {
            'data': {'write_checkpoint': '1'}
          };

      final query = StreamQueue(database
          .watch('SELECT name FROM customers')
          .map((e) => e.single['name']));
      expect(await query.next, 'local customer');

      await waitForConnection();

      syncService
        ..addLine({
          'checkpoint': Checkpoint(
            lastOpId: '1',
            writeCheckpoint: '1',
            checksums: [BucketChecksum(bucket: 'a', priority: 3, checksum: 0)],
          )
        })
        ..addLine({
          'data': {
            'bucket': 'a',
            'data': <Map<String, Object?>>[
              {
                'op_id': '1',
                'op': 'PUT',
                'object_type': 'customers',
                'object_id': '1',
                'checksum': 0,
                'data': json.encode({'name': 'from server'}),
              }
            ],
          }
        })
        ..addLine({
          'checkpoint_complete': {'last_op_id': '1'}
        });

      expect(await query.next, 'from server');
    });

    group('abort', () {
      test('during connect', () async {
        final requestStarted = Completer<void>();

        syncService.router = Router()
          ..post('/sync/stream', expectAsync1((Request request) async {
            requestStarted.complete();

            // emulate a network that never connects
            await Completer<void>().future;
          }));

        syncClient.streamingSync();
        await requestStarted.future;
        expect(database.currentStatus, isSyncStatus(connecting: true));

        await syncClient.abort();
        expect(database.currentStatus.anyError, isNull);
      });

      test('during stream', () async {
        final status = await waitForConnection();
        syncService.addLine({
          'checkpoint': {
            'last_op_id': '0',
            'buckets': [
              {
                'bucket': 'bkt',
                'checksum': 0,
              }
            ],
          },
        });
        await expectLater(status, emits(isSyncStatus(downloading: true)));

        await syncClient.abort();
        expect(database.currentStatus.anyError, isNull);
      });
    });
  });
}

TypeMatcher<SyncStatus> isSyncStatus({
  Object? downloading,
  Object? connected,
  Object? connecting,
  Object? hasSynced,
  Object? downloadProgress,
}) {
  var matcher = isA<SyncStatus>();
  if (downloading != null) {
    matcher = matcher.having((e) => e.downloading, 'downloading', downloading);
  }
  if (connected != null) {
    matcher = matcher.having((e) => e.connected, 'connected', connected);
  }
  if (connecting != null) {
    matcher = matcher.having((e) => e.connecting, 'connecting', connecting);
  }
  if (hasSynced != null) {
    matcher = matcher.having((e) => e.hasSynced, 'hasSynced', hasSynced);
  }
  if (downloadProgress != null) {
    matcher = matcher.having(
        (e) => e.downloadProgress, 'downloadProgress', downloadProgress);
  }

  return matcher;
}

TypeMatcher<SyncDownloadProgress> isSyncDownloadProgress({
  required Object progress,
  Map<BucketPriority, Object> priorities = const {},
}) {
  var matcher =
      isA<SyncDownloadProgress>().having((e) => e, 'untilCompletion', progress);
  priorities.forEach((priority, expected) {
    matcher = matcher.having(
        (e) => e.untilPriority(priority), 'untilPriority($priority)', expected);
  });

  return matcher;
}

TypeMatcher<ProgressWithOperations> progress(int completed, int total) {
  return isA<ProgressWithOperations>()
      .having((e) => e.downloadedOperations, 'completed', completed)
      .having((e) => e.totalOperations, 'total', total);
}
