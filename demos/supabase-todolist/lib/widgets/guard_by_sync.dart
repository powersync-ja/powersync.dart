import 'package:flutter/material.dart';
import 'package:powersync/powersync.dart' hide Column;
import 'package:powersync_flutter_demo/powersync.dart';

/// A widget that shows [child] after a complete sync on the database has
/// completed and a progress bar before that.
class GuardBySync extends StatelessWidget {
  final Widget child;

  /// When set, wait only for a complete sync within the [StreamPriority]
  /// instead of a full sync.
  final StreamPriority? priority;

  const GuardBySync({
    super.key,
    required this.child,
    this.priority,
  });

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<SyncStatus>(
      stream: db.statusStream,
      initialData: db.currentStatus,
      builder: (context, snapshot) {
        final status = snapshot.requireData;
        final (didSync, progress) = switch (priority) {
          null => (status.hasSynced ?? false, status.downloadProgress),
          var priority? => (
              status.statusForPriority(priority).hasSynced ?? false,
              status.downloadProgress?.untilPriority(priority)
            ),
        };

        if (didSync) {
          return child;
        } else {
          return Center(
            child: Column(
              children: [
                const Text('Busy with sync...'),
                LinearProgressIndicator(value: progress?.downloadedFraction),
                if (progress case final progress?)
                  Text(
                      '${progress.downloadedOperations} out of ${progress.totalOperations}')
              ],
            ),
          );
        }
      },
    );
  }
}
