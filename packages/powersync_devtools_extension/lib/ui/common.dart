import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/material.dart';
import 'package:powersync_devtools_extension/state/databases.dart';

final class HasDatabaseGuard extends ConsumerWidget {
  final Widget child;

  const HasDatabaseGuard({super.key, required this.child});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final databases = ref.watch(databaseList);

    if (databases.isLoading) {
      return Center(child: CircularProgressIndicator());
    }

    if (databases.error case final error?) {
      return Text('Could not list databases: $error');
    }

    if (databases.hasValue && databases.requireValue.isEmpty) {
      return Text('No PowerSyncDatabase instances found in app.');
    }

    return child;
  }
}
