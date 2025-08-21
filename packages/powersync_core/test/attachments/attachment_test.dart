import 'dart:typed_data';

import 'package:async/async.dart';
import 'package:logging/logging.dart';
import 'package:mockito/mockito.dart';
import 'package:powersync_core/attachments/attachments.dart';
import 'package:powersync_core/powersync_core.dart';
import 'package:test/test.dart';

import '../utils/abstract_test_utils.dart';
import '../utils/test_utils_impl.dart';

void main() {
  late TestPowerSyncFactory factory;
  late PowerSyncDatabase db;
  late MockRemoteStorage remoteStorage;
  late LocalStorage localStorage;
  late AttachmentQueue queue;
  late StreamQueue<List<Attachment>> attachments;

  Stream<List<WatchedAttachmentItem>> watchAttachments() {
    return db
        .watch('SELECT photo_id FROM users WHERE photo_id IS NOT NULL')
        .map(
          (rs) => [
            for (final row in rs)
              WatchedAttachmentItem(
                  id: row['photo_id'] as String, fileExtension: 'jpg')
          ],
        );
  }

  setUpAll(() async {
    factory = await TestUtils().testFactory();
  });

  setUp(() async {
    remoteStorage = MockRemoteStorage();
    localStorage = LocalStorage.inMemory();

    final (raw, database) = await factory.openInMemoryDatabase(
      schema: _schema,
      // Uncomment to see test logs
      logger: Logger.detached('PowerSyncTest'),
    );
    await database.initialize();
    db = database;

    queue = AttachmentQueue(
      db: db,
      remoteStorage: remoteStorage,
      watchAttachments: watchAttachments,
      localStorage: localStorage,
      archivedCacheLimit: 0,
    );

    attachments = StreamQueue(db.attachments);
    await expectLater(attachments, emits(isEmpty));
  });

  tearDown(() async {
    await attachments.cancel();
    await queue.stopSyncing();
    await queue.close();

    await db.close();
  });

  test('downloads attachments', () async {
    await queue.startSync();

    // Create a user with a photo_id specified. Since we didn't save an
    // attachment before assigning a photo_id, this is equivalent to reuqiring
    // an attachment download.
    await db.execute(
      'INSERT INTO users (id, name, email, photo_id) VALUES (uuid(), ?, ?, uuid())',
      ['steven', 'steven@journeyapps.com'],
    );

    var [attachment] = await attachments.next;
    if (attachment.state == AttachmentState.queuedDownload) {
      // Depending on timing with the queue scanning for items asynchronously,
      // we may see a queued download or a synced event initially.
      [attachment] = await attachments.next;
    }

    expect(attachment.state, AttachmentState.synced);
    final localUri = attachment.localUri!;

    // A download should he been attempted for this file.
    verify(remoteStorage.downloadFile(argThat(isAttachment(attachment.id))));

    // A file should now exist.
    expect(await localStorage.fileExists(localUri), isTrue);

    // Now clear the user's photo_id, which should archive the attachment.
    await db.execute('UPDATE users SET photo_id = NULL');

    var nextAttachment = (await attachments.next).firstOrNull;
    if (nextAttachment != null) {
      expect(nextAttachment.state, AttachmentState.archived);
      nextAttachment = (await attachments.next).firstOrNull;
    }

    expect(nextAttachment, isNull);

    // File should have been deleted too
    expect(await localStorage.fileExists(localUri), isFalse);
  });

  test('uploads attachments', () async {
    await queue.startSync();

    final record = await queue.saveFile(
      data: Stream.value(Uint8List(123)),
      mediaType: 'image/jpg',
      updateHook: (tx, attachment) async {
        await tx.execute(
          'INSERT INTO users (id, name, email, photo_id) VALUES (uuid(), ?, ?, ?);',
          ['steven', 'steven@journeyapps.com', attachment.id],
        );
      },
    );
    expect(record.size, 123);

    var [attachment] = await attachments.next;
    if (attachment.state == AttachmentState.queuedUpload) {
      // Wait for it to be synced
      [attachment] = await attachments.next;
    }

    expect(attachment.state, AttachmentState.synced);

    // An upload should have been attempted for this file.
    verify(remoteStorage.uploadFile(any, argThat(isAttachment(record.id))));
    expect(await localStorage.fileExists(record.localUri!), isTrue);

    // Now clear the user's photo_id, which should archive the attachment.
    await db.execute('UPDATE users SET photo_id = NULL');

    // Should delete attachment from database
    await expectLater(attachments, emitsThrough(isEmpty));

    // File should have been deleted too
    expect(await localStorage.fileExists(record.localUri!), isFalse);
  });

  test('delete attachments', () async {
    await queue.startSync();

    final id = await queue.generateAttachmentId();
    await db.execute(
      'INSERT INTO users (id, name, email, photo_id) VALUES (uuid(), ?, ?, ?)',
      ['steven', 'steven@journeyapps.com', id],
    );

    // Wait for the attachment to be synced.
    await expectLater(
      attachments,
      emitsThrough([
        isA<Attachment>()
            .having((e) => e.state, 'state', AttachmentState.synced)
      ]),
    );

    await queue.deleteFile(
      attachmentId: id,
      updateHook: (tx, attachment) async {
        await tx.execute(
          'UPDATE users SET photo_id = NULL WHERE photo_id = ?',
          [attachment.id],
        );
      },
    );

    // Record should be deleted.
    await expectLater(attachments, emitsThrough(isEmpty));
    verify(remoteStorage.deleteFile(argThat(isAttachment(id))));
  });

  test('cached download', () async {
    queue = AttachmentQueue(
      db: db,
      remoteStorage: remoteStorage,
      watchAttachments: watchAttachments,
      localStorage: localStorage,
      archivedCacheLimit: 10,
    );

    await queue.startSync();

    // Create attachment and wait for download.
    await db.execute(
      'INSERT INTO users (id, name, email, photo_id) VALUES (uuid(), ?, ?, uuid())',
      ['steven', 'steven@journeyapps.com'],
    );
    await expectLater(
      attachments,
      emitsThrough([
        isA<Attachment>()
            .having((e) => e.state, 'state', AttachmentState.synced)
      ]),
    );
    final [id as String, localUri as String] =
        (await db.get('SELECT id, local_uri FROM attachments_queue')).values;
    verify(remoteStorage.downloadFile(argThat(isAttachment(id))));
    expect(await localStorage.fileExists(localUri), isTrue);

    // Archive attachment by not referencing it anymore.
    await db.execute('UPDATE users SET photo_id = NULL');
    await expectLater(
      attachments,
      emitsThrough([
        isA<Attachment>()
            .having((e) => e.state, 'state', AttachmentState.archived)
      ]),
    );

    // Restore from cache
    await db.execute('UPDATE users SET photo_id = ?', [id]);
    await expectLater(
      attachments,
      emitsThrough([
        isA<Attachment>()
            .having((e) => e.state, 'state', AttachmentState.synced)
      ]),
    );
    expect(await localStorage.fileExists(localUri), isTrue);

    // Should not have downloaded attachment again because we have it locally.
    verifyNoMoreInteractions(remoteStorage);
  });

  test('skip failed download', () async {
    Future<bool> errorHandler(
        Attachment attachment, Object exception, StackTrace trace) async {
      return false;
    }

    queue = AttachmentQueue(
      db: db,
      remoteStorage: remoteStorage,
      watchAttachments: watchAttachments,
      localStorage: localStorage,
      errorHandler: AttachmentErrorHandler(
        onDeleteError: expectAsync3(errorHandler, count: 0),
        onDownloadError: expectAsync3(errorHandler, count: 1),
        onUploadError: expectAsync3(errorHandler, count: 0),
      ),
    );

    when(remoteStorage.downloadFile(any)).thenAnswer((_) async {
      throw 'test error';
    });

    await queue.startSync();
    await db.execute(
      'INSERT INTO users (id, name, email, photo_id) VALUES (uuid(), ?, ?, uuid())',
      ['steven', 'steven@journeyapps.com'],
    );

    expect(await attachments.next, [
      isA<Attachment>()
          .having((e) => e.state, 'state', AttachmentState.queuedDownload)
    ]);
    expect(await attachments.next, [
      isA<Attachment>()
          .having((e) => e.state, 'state', AttachmentState.archived)
    ]);
  });
}

extension on PowerSyncDatabase {
  Stream<List<Attachment>> get attachments {
    return watch('SELECT * FROM attachments_queue')
        .map((rs) => rs.map(Attachment.fromRow).toList());
  }
}

final class MockRemoteStorage extends Mock implements RemoteStorage {
  MockRemoteStorage() {
    when(uploadFile(any, any)).thenAnswer((_) async {});
    when(downloadFile(any)).thenAnswer((_) async {
      return Stream.empty();
    });
    when(deleteFile(any)).thenAnswer((_) async {});
  }

  @override
  Future<void> uploadFile(
      Stream<Uint8List>? fileData, Attachment? attachment) async {
    await noSuchMethod(Invocation.method(#uploadFile, [fileData, attachment]));
  }

  @override
  Future<Stream<List<int>>> downloadFile(Attachment? attachment) {
    return (noSuchMethod(Invocation.method(#downloadFile, [attachment])) ??
            Future.value(const Stream<List<int>>.empty()))
        as Future<Stream<List<int>>>;
  }

  @override
  Future<void> deleteFile(Attachment? attachment) async {
    await noSuchMethod(Invocation.method(#deleteFile, [attachment]));
  }
}

final _schema = Schema([
  Table('users',
      [Column.text('name'), Column.text('email'), Column.text('photo_id')]),
  AttachmentsQueueTable(),
]);

TypeMatcher<Attachment> isAttachment(String id) {
  return isA<Attachment>().having((e) => e.id, 'id', id);
}
