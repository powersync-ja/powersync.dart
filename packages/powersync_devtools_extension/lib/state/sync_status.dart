import 'dart:async';

import 'package:powersync/powersync.dart';
import 'package:powersync_devtools_extension/state/databases.dart';
import 'package:riverpod/riverpod.dart';

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

final isWaitingForCheckpoint = StreamProvider.autoDispose<bool>((ref) {
  final db = ref.watch(selectedDatabase);
  if (db != null) {
    return db
        .watchUnthrottled(
          r"SELECT 1 FROM ps_buckets WHERE target_op > last_op AND name = '$local'",
        )
        .map((rs) => rs.isNotEmpty);
  } else {
    return Stream.empty();
  }
});

final uploadStatus = Provider<String>((ref) {
  final outstandingCrudItems = ref.watch(pendingCrudItems);
  final waitingForCheckpoint = ref.watch(isWaitingForCheckpoint);
  final status = ref.watch(syncStatus);
  if (status == null) return 'unknown';

  final description = StringBuffer();
  if (outstandingCrudItems.value case final value? when value > 0) {
    description.write(
      '⚠ $value local writes prevent new data from being synced. ',
    );
  } else if (waitingForCheckpoint.value == true) {
    description.write(
      'Waiting for a write checkpoint containing the previous upload. ',
    );
  }

  if (status.uploadError case final error?) {
    description.write('Upload error: $error');
  } else if (status.uploading) {
    description.write('Waiting for uploadData()');
  }
  return description.toString();
});
