import 'package:powersync/powersync.dart';

const schema = Schema(([
  Table('todos', [
    Column.text('list_id'),
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
  Table('lists',
      [Column.text('created_at'), Column.text('name'), Column.text('owner_id')])
]));
