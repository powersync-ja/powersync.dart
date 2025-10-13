import 'package:powersync/powersync.dart';
import 'package:powersync_core/attachments/attachments.dart';

const todosTable = 'todos';

Schema schema = Schema(
  [
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
    AttachmentsQueueTable()
  ],
  rawTables: [
    RawTable(
      name: 'lists',
      put: PendingStatement(
        sql:
            'INSERT OR REPLACE INTO lists (id, created_at, name, owner_id) VALUES (?, ?, ?, ?)',
        params: [
          PendingStatementValue.id(),
          PendingStatementValue.column('created_at'),
          PendingStatementValue.column('name'),
          PendingStatementValue.column('owner_id'),
        ],
      ),
      delete: PendingStatement(sql: 'DELETE FROM lists WHERE id = ?', params: [
        PendingStatementValue.id(),
      ]),
    )
  ],
);
