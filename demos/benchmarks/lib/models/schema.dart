import 'package:powersync/powersync.dart';

Schema schema = const Schema(([
  Table('benchmark_items', [
    Column.text('description'),
    Column.text('client_created_at'),
    Column.text('client_received_at'),
    Column.text('server_created_at'),
  ]),
  // We don't query this, but we do sync these.
  // This is used to test large db sizes without having many
  // benchmark_items.
  Table('lists', [Column.text('name')]),
]));
