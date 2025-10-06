## Attachments

In many cases, you might want to sync large binary data (like images) along with the data synced by
PowerSync.
Embedding this data directly in your source databases is [inefficient and not recommended](https://docs.powersync.com/usage/use-case-examples/attachments).

Instead, the PowerSync SDK for Dart and Flutter provides utilities you can use to _reference_ this binary data
in your regular database schema, and then download it from a secondary data store such as Supabase Storage or S3.
Because binary data is not directly stored in the source database in this model, we call these files _attachments_.


> [!NOTE]  
> These attachment utilities are recommended over our legacy [PowerSync Attachments Helper](https://pub.dev/packages/powersync_attachments_helper) package. The new utilities provide cleaner APIs that are more aligned with similar helpers in our other SDKs, and include improved features such as:
> - Support for writing your own local storage implementation
> - Support for dynamic nested directories and custom per-attachment file extensions out of the box
> - Ability to add optional `metaData` to attachments
> - No longer depends on `dart:io` 
> 
> If you are new to handling attachments, we recommend starting with these utilities. If you currently use the legacy `powersync_attachments_helper` package, a fairly simple migration would be to adopt the new utilities with a different table name and drop the legacy package. This means existing attachments are lost, but they should be downloaded again.

## Alpha release

The attachment utilities described in this document are currently in an alpha state, intended for testing.
Expect breaking changes and instability as development continues.
The attachments API is marked as `@experimental` for this reason.

Do not rely on these utilities for production use.

## Usage

An `AttachmentQueue` instance is used to manage and sync attachments in your app.
The attachments' state is stored in a local-only attachments table.

### Key assumptions

- Each attachment is identified by a unique id.
- Attachments are immutable once created.
- Relational data should reference attachments using a foreign key column.
- Relational data should reflect the holistic state of attachments at any given time. Any existing local attachment
  will be deleted locally if no relational data references it.

### Example implementation

See the [supabase-todolist](https://github.com/powersync-ja/powersync.dart/tree/main/demos/supabase-todolist) demo for a basic example of attachment syncing.

In particular, relevant snippets from that example are:

- The attachment queue is set up [here](https://github.com/powersync-ja/powersync.dart/blob/98d73e2f157a697786373fef755576505abc74a5/demos/supabase-todolist/lib/attachments/queue.dart#L16-L36), using conditional imports to store attachments in the file system on native platforms and in-memory for web.
- When a new attachment is added, `saveFile` is called [here](https://github.com/powersync-ja/powersync.dart/blob/98d73e2f157a697786373fef755576505abc74a5/demos/supabase-todolist/lib/attachments/queue.dart#L38-L55) and automatically updates references in the main schema to reference the attachment.

### Setup

First, add a table storing local attachment state to your database schema.

```dart
final schema = Schema([
  AttachmentsQueueTable(),
  // In this document, we assume the photo_id column of the todos table references an optional photo
  // stored as an attachment.
  Table('todos', [
    Column.text('list_id'),
    Column.text('photo_id'),
    Column.text('description'),
    Column.integer('completed'),
  ]),
]);
```

Next, create an `AttachmentQueue` instance. This class provides default syncing utilities and implements a default
sync strategy. This class can be extended for custom functionality, if needed.

```dart
final directory = await getApplicationDocumentsDirectory();

final attachmentQueue = AttachmentQueue(
  db: db,
  remoteStorage: SupabaseStorageAdapter(), // instance responsible for uploads and downloads
  logger: logger,
  localStorage: IOLocalStorage(appDocDir), // IOLocalStorage requires `dart:io` and is not available on the web
   watchAttachments: () => db.watch('''
      SELECT photo_id as id FROM todos WHERE photo_id IS NOT NULL
   ''').map((results) => [
      for (final row in results)
        WatchedAttachmentItem(
          id: row['id'] as String,
          fileExtension: 'jpg',
        )
      ],
    ),
);
```

Here,
 - An instance of `LocalStorageAdapter`, such as the `IOLocalStorage` provided by the SDK, is responsible for storing
   attachment contents locally.
 - An instance of `RemoteStorageAdapter` is responsible for downloading and uploading attachment contents to the secondary
   service, such as S3, Firebase cloud storage or Supabase storage.
 - `watchAttachments` is a function emitting a stream of attachment items that are considered to be referenced from
   the current database state. In this example, `todos.photo_id` is the only column referencing attachments.

Next, start the sync process by calling `attachmentQueue.startSync()`.

## Storing attachments

To create a new attachment locally, call `AttachmentQueue.saveFile`. To represent the attachment, this method takes
the contents to store, the media type, an optional file extension and id.
The queue will store the contents in a local file and mark it as queued for upload. It also invokes a callback
responsible for referencing the id of the generated attachment in the primary data model:

```dart
Future<Attachment> savePhotoAttachment(
    Stream<List<int>> photoData, String todoId,
    {String mediaType = 'image/jpeg'}) async {
  // Save the file using the AttachmentQueue API
  return await attachmentQueue.saveFile(
    data: photoData,
    mediaType: mediaType,
    fileExtension: 'jpg',
    metaData: 'Photo attachment for todo: $todoId',
    updateHook: (context, attachment) async {
      // Update the todo item to reference this attachment
      await context.execute(
        'UPDATE todos SET photo_id = ? WHERE id = ?',
        [attachment.id, todoId],
      );
    },
  );
}
```

## Deleting attachments

To delete attachments, it is sufficient to stop referencing them in the data model, e.g. via
`UPDATE todos SET photo_id = NULL` in this example. The attachment sync implementation will eventually
delete orphaned attachments from the local storage.
