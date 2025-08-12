# PowerSync Attachment Stream

A [PowerSync](https://powersync.com) library to manage attachments (such as images or files) in Dart apps.


### Alpha Release

Attachment stream is currently in an alpha state, intended strictly for testing. Expect breaking changes and instability as development continues.

Do not rely on this package for production use.

## Usage

An `AttachmentQueue` is used to manage and sync attachments in your app. The attachments' state is stored in a local-only attachments table.

### Key Assumptions

- Each attachment is identified by a unique ID
- Attachments are immutable once created
- Relational data should reference attachments using a foreign key column
- Relational data should reflect the holistic state of attachments at any given time. An existing local attachment will be deleted locally if no relational data references it.

### Example Implementation

See the [Flutter Supabase Demo](../../demos/supabase-todolist/README.md) for a basic example of attachment syncing.

In the example below, the user captures photos when checklist items are completed as part of an inspection workflow.

1. First, define your schema including the `checklist` table and the local-only attachments table:

```dart
Schema schema = Schema(([
  const Table('checklists', [
    Column.text('description'),
    Column.integer('completed'),
    Column.text('photo_id'),
  ]),
  AttachmentsQueueTable(
      attachmentsQueueTableName: defaultAttachmentsQueueTableName)
]));
```

2. Create an `AttachmentQueue` instance. This class provides default syncing utilities and implements a default sync strategy. This class is open and can be overridden for custom functionality:

```dart
final Directory appDocDir = await getApplicationDocumentsDirectory();
final localStorage = IOLocalStorage('${appDocDir.path}/attachments');

final queue = AttachmentQueue(
    db: db,
    remoteStorage: remoteStorage,
    localStorage: localStorage,
    watchAttachments: () => db.watch('''
      SELECT photo_id as id FROM todos WHERE photo_id IS NOT NULL
    ''').map((results) => results
        .map((row) => WatchedAttachmentItem(
              id: row['id'] as String,
              fileExtension: 'jpg',
            ))
        .toList()),
  );
```

* The `localStorage` is an implementation of `AbstractLocalStorageAdapter` that specifies where and how local attachment files should be stored. For mobile and desktop apps, `IOLocalStorage` can be used, which requires a directory path. In Flutter, `path_provider`'s `getApplicationDocumentsDirectory()` with a subdirectory like `/attachments` is a good choice.
* The `remoteStorage` is responsible for connecting to the attachments backend. See the `RemoteStorageAdapter` interface definition [here](https://github.com/powersync-ja/powersync.dart/blob/main/packages/powersync_attachments_stream/lib/src/abstractions/remote_storage.dart).
* `watchAttachments` is a `Stream` of `WatchedAttachmentItem`. The `WatchedAttachmentItem`s represent the attachments which should be present in the application. We recommend using `PowerSync`'s `watch` query as shown above. In this example, we provide the `fileExtension` for all photos. This information could also be obtained from the query if necessary.

3. Implement a `RemoteStorageAdapter` which interfaces with a remote storage provider. This will be used for downloading, uploading, and deleting attachments:

```dart
final remote = _RemoteStorageAdapter();

class _RemoteStorageAdapter implements AbstractRemoteStorageAdapter {
  @override
  Future<void> uploadFile(Stream<List<int>> fileData, Attachment attachment) async {
    // TODO: Implement upload to your backend
  }

  @override
  Future<Stream<List<int>>> downloadFile(Attachment attachment) async {
    // TODO: Implement download from your backend
  }

  @override
  Future<void> deleteFile(Attachment attachment) async {
    // TODO: Implement delete in your backend
  }
}
```

4. Start the sync process:

```dart
await queue.startSync();
```

5. Create and save attachments using `saveFile()`. This method will save the file to local storage, create an attachment record which queues the file for upload to the remote storage, and allows assigning the newly created attachment ID to a checklist item:

```dart
await queue.saveFile(
    data: photoData,
    mediaType: 'image/jpg',
    fileExtension: 'jpg',
    metaData: 'Test meta data',
    updateHook: (context, attachment) async {
      // Update the todo item to reference this attachment
      await context.execute(
        'UPDATE checklists SET photo_id = ? WHERE id = ?',
        [attachment.id, checklistId],
      );
    },
  );
```

## Implementation Details

### Attachment Table Structure

The `AttachmentsQueueTable` class creates a **local-only table** for tracking the states and metadata of file attachments. It allows customization of the table name, additional columns, indexes, and optionally a view name.

An attachments table definition can be created with the following options:

| Option                 | Description                     | Default                      |
| ---------------------- | -------------------------------| ----------------------------|
| `attachmentsQueueTableName` | The name of the table          | `defaultAttachmentsQueueTableName` |
| `additionalColumns`    | Extra columns to add to the table | `[]` (empty list)            |
| `indexes`              | Indexes to optimize queries     | `[]` (empty list)            |
| `viewName`             | Optional associated view name   | `null`                       |

The default columns included in the table are:

| Column Name  | Type      | Description                                                                      |
| ------------ | --------- | -------------------------------------------------------------------------------- |
| `filename`   | `TEXT`    | The filename of the attachment                                                   |
| `local_uri`  | `TEXT`    | Local file URI or path                                                           |
| `timestamp`  | `INTEGER` | The timestamp of the last update to the attachment                               |
| `size`       | `INTEGER` | File size in bytes                                                               |
| `media_type` | `TEXT`    | The media (MIME) type of the attachment                                          |
| `state`      | `INTEGER` | Current state of the attachment (e.g., queued, syncing, synced)                  |
| `has_synced` | `INTEGER` | Internal flag indicating if the attachment has ever been synced (for caching)    |
| `meta_data`  | `TEXT`    | Additional metadata stored as JSON                                               |

The class extends a base `Table` class using a `localOnly` constructor, so this table exists **only locally** on the device and is not synchronized with a remote database.

This design allows flexible tracking and management of attachment syncing state and metadata within the local database.                                               |

### Attachment States

Attachments are managed through the following states, which represent their current synchronization status with remote storage:

| State             | Description                                                            |
| ----------------- | ---------------------------------------------------------------------- |
| `queuedUpload`    | Attachment is queued for upload to remote/cloud storage                |
| `queuedDelete`    | Attachment is queued for deletion from both remote and local storage   |
| `queuedDownload`  | Attachment is queued for download from remote/cloud storage            |
| `synced`          | Attachment is fully synchronized with remote storage                   |
| `archived`        | Attachment is archived — no longer actively synchronized or referenced |

---

The `AttachmentState` enum also provides helper methods for converting between the enum and its integer representation:

- `AttachmentState.fromInt(int value)` — Constructs an `AttachmentState` from its corresponding integer index. Throws an `ArgumentError` if the value is out of range.
- `toInt()` — Returns the integer index of the current `AttachmentState` instance.

### Sync Process

The `AttachmentQueue` implements a sync process with these components:

1. **State Monitoring**: The queue watches the attachments table for records in `queuedUpload`, `queuedDelete`, and `queuedDownload` states. An event loop triggers calls to the remote storage for these operations.

2. **Periodic Sync**: By default, the queue triggers a sync every 30 seconds to retry failed uploads/downloads, in particular after the app was offline. This interval can be configured by setting `syncInterval` in the `AttachmentQueue` constructor options, or disabled by setting the interval to `0`.

3. **Watching State**: The `watchAttachments` stream in the `AttachmentQueue` constructor is used to maintain consistency between local and remote states:
   - New items trigger downloads - see the Download Process below.
   - Missing items trigger archiving - see Cache Management below.

### Upload Process

The `saveFile` method handles attachment creation and upload:

1. The attachment is saved to local storage
2. An `AttachmentRecord` is created with `queuedUpload` state, linked to the local file using `localUri`
3. The attachment must be assigned to relational data in the same transaction, since this data is constantly watched and should always represent the attachment queue state
4. The `RemoteStorageAdapter` `uploadFile` function is called
5. On successful upload, the state changes to `synced`
6. If upload fails, the record stays in `queuedUpload` state for retry

### Download Process

Attachments are scheduled for download when the stream from `watchAttachments` emits a new item that is not present locally:

1. An `AttachmentRecord` is created with `queuedDownload` state
2. The `RemoteStorageAdapter` `downloadFile` function is called
3. The received data is saved to local storage
4. On successful download, the state changes to `synced`
5. If download fails, the operation is retried in the next sync cycle

### Delete Process

The `deleteFile` method deletes attachments from both local and remote storage:

1. The attachment record moves to `queuedDelete` state
2. The attachment must be unassigned from relational data in the same transaction, since this data is constantly watched and should always represent the attachment queue state
3. On successful deletion, the record is removed
4. If deletion fails, the operation is retried in the next sync cycle

### Cache Management

The `AttachmentQueue` implements a caching system for archived attachments:

1. Local attachments are marked as `archived` if the stream from `watchAttachments` no longer references them
2. Archived attachments are kept in the cache for potential future restoration
3. The cache size is controlled by the `archivedCacheLimit` parameter in the `AttachmentQueue` constructor
4. By default, the queue keeps the last 100 archived attachment records
5. When the cache limit is reached, the oldest archived attachments are permanently deleted
6. If an archived attachment is referenced again while still in the cache, it can be restored
7. The cache limit can be configured in the `AttachmentQueue` constructor

### Error Handling

1. **Automatic Retries**:
   - Failed uploads/downloads/deletes are automatically retried
   - The sync interval (default 30 seconds) ensures periodic retry attempts
   - Retries continue indefinitely until successful

2. **Custom Error Handling**:
   - A `SyncErrorHandler` can be implemented to customize retry behavior (see example below)
   - The handler can decide whether to retry or archive failed operations
   - Different handlers can be provided for upload, download, and delete operations

Example of a custom `SyncErrorHandler`:

```dart
final errorHandler = _SyncErrorHandler();

class _SyncErrorHandler implements AbstractSyncErrorHandler {
  @override
  Future<bool> onDownloadError(Attachment attachment, Object exception) async {
    // TODO: Return if the attachment sync should be retried
    return false;
  }

  @override
  Future<bool> onUploadError(Attachment attachment, Object exception) async {
    // TODO: Return if the attachment sync should be retried
    return false;
  }

  @override
  Future<bool> onDeleteError(Attachment attachment, Object exception) async {
    // TODO: Return if the attachment sync should be retried
    return false;
  }
}

final queue = AttachmentQueue(
  // ... other parameters ...
  errorHandler: errorHandler,
);
```