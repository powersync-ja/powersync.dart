import 'package:powersync/powersync.dart';
import 'package:powersync_attachments_helper/powersync_attachments_helper.dart';

const todosTable = 'todos';

Schema schema = Schema(([
  const Table(todosTable, [
    Column.text('list_id'),
    Column.text('photo_id'),
    Column.text('created_at'),
    Column.text('completed_at'),
    Column.text('description'),
    Column.integer('completed'),
    Column.text('created_by'),
    Column.text('completed_by'),
  ], indexes: [
    // Index to allow efficient lookup within a list
    Index('list', [IndexedColumn('list_id')])
  ]),
  const Table('lists', [
    Column.text('created_at'),
    Column.text('name'),
    Column.text('owner_id')
  ]),
  AttachmentsQueueTable(
      attachmentsQueueTableName: defaultAttachmentsQueueTableName)
]));
