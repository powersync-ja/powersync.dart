import 'package:powersync/powersync.dart';

Schema schema = const Schema(([
  Table('benchmark_items', [
    Column.text('description'),
    Column.text('client_created_at'),
    Column.text('client_received_at'),
    Column.text('server_created_at'),
  ]),
]));
