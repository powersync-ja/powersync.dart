import 'dart:async';
import 'dart:js_interop';

import 'package:powersync/powersync.dart';
import 'package:riverpod/riverpod.dart';

import '../integration/types.dart';
import 'databases.dart';

final class _SyncStatusNotifier extends Notifier<SyncStatus?> {
  StreamSubscription<SyncStatus>? _updates;

  @override
  SyncStatus? build() {
    final db = ref.watch(selectedDatabase);
    _updates?.cancel();
    _updates = null;

    if (db != null) {
      final subscription = _updates = db.syncStatus.listen((status) {
        state = status;
      });
      ref.onDispose(subscription.cancel);
    }

    return db?.currentStatus;
  }
}

final syncStatus = NotifierProvider(_SyncStatusNotifier.new);

/// How many items we currently have in `ps_crud`.
final pendingCrudItems = StreamProvider.autoDispose<int>((ref) {
  final db = ref.watch(selectedDatabase);
  if (db != null) {
    return db
        .watchUnthrottled('SELECT COUNT(*) FROM ps_crud')
        .map((rs) => rs[0].columnAt(0) as int);
  } else {
    return Stream.empty();
  }
});

final bucketState = StreamProvider.autoDispose<List<BucketState>>((ref) {
  final db = ref.watch(selectedDatabase);
  if (db != null) {
    return db
        .watchUnthrottled(
          'SELECT name, count_at_last+count_since_last, downloaded_size, CAST(last_op AS TEXT) FROM ps_buckets',
        )
        .map((rs) {
          return [
            for (final row in rs)
              BucketState(
                name: row.columnAt(0) as String,
                downloadedOperations: row.columnAt(1) as int,
                downloadedSize: row.columnAt(2) as int,
                lastOp: row.columnAt(3) as String,
                // TODO: track via diagnostics stream
                totalOperations: null,
                downloading: false,
              ),
          ];
        });
  } else {
    return Stream.empty();
  }
});

extension DiagnosticsStatus on SyncStatus {
  SyncState toDiagnosticsSyncState() {
    return SyncState(
      connected: connected,
      connecting: connecting,
      downloading: downloading,
      uploading: uploading,
      hasSynced: hasSynced,
      lastSyncedAt: lastSyncedAt?.millisecondsSinceEpoch,
      downloadProgress: downloadProgress?._toJs(),
      priorities: <PriorityState>[
        for (final priority in priorityStatusEntries)
          PriorityState(
            priority: priority.priority.priorityNumber,
            lastSyncedAt: lastSyncedAt?.millisecondsSinceEpoch,
            hasSynced: hasSynced,
          ),
      ].toJS,
      downloadError: downloadError?.toString(),
      uploadError: uploadError?.toString(),
      message: '',
    );
  }
}

extension DiagnosticsStream on SyncStreamStatus {
  StreamState toStreamState() {
    final stream = subscription;

    return StreamState(
      name: stream.name,
      priority: priority.priorityNumber,
      active: stream.active,
      autoSubscribed: stream.isDefault,
      explicitlySubscribed: stream.hasExplicitSubscription,
      progress: progress?._toJs(),
      params: subscription.parameters.jsify() as JSObject?,
      expiresAt: stream.expiresAt?.millisecondsSinceEpoch,
      hasSynced: stream.hasSynced,
      lastSyncedAt: stream.lastSyncedAt?.millisecondsSinceEpoch,
    );
  }
}

extension on ProgressWithOperations {
  ProgressState _toJs() {
    return ProgressState(
      downloadedOperations: downloadedOperations,
      totalOperations: totalOperations,
      downloadedFraction: downloadedFraction,
    );
  }
}
