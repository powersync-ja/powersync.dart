import 'package:powersync/powersync.dart';

const schema = Schema(([
  Table('lists', [
    Column.text('created_at'),
    Column.text('name'),
    Column.text('owner_id')
  ]),
]));
