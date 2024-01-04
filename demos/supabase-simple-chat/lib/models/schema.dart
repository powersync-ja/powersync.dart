import 'package:powersync/powersync.dart';

const schema = Schema([
  Table('messages', [
    Column.text('profile_id'),
    Column.text('content'),
    Column.text('created_at')
  ]),
  Table('profiles', [Column.text('username'), Column.text('created_at')])
]);
