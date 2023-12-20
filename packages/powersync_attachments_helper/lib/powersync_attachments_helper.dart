/// Attachment Helper SDK.
///
/// Implement [AbstractAttachmentQueue] to create an attachment queue.
library;

export 'src/attachments_queue.dart';
export 'src/remote_storage_adapter.dart' show AbstractRemoteStorageAdapter;
export 'src/attachments_queue_table.dart'
    show Attachment, AttachmentState, AttachmentsQueueTable;
