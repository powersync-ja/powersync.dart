import 'package:powersync/powersync.dart';

const schema = Schema(([
  Table('counter', [
    Column.text('user_id'),
    Column.text('count')
  ])
]));