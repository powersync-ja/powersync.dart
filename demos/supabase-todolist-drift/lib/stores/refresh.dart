// ignore_for_file: experimental_member_use

import 'package:riverpod/experimental/mutation.dart';
import 'package:riverpod/riverpod.dart';

import '../app_config.dart';
import '../powersync/powersync.dart';

final refresh = Mutation(label: 'explicit sync');

/// Whether a checkpoint request can be sent from the current database state.
///
/// This is the case if checkpoint requests are enabled and the database is
/// connected. For this demo, we also avoid concurrent checkpoint refresh runs.
final canRefresh = Provider<bool>((ref) {
  if (!AppConfig.enableCheckpointRequests) return false;

  if (ref.watch(refresh).isPending) return false;

  final status = ref.watch(syncStatus);
  return status.connected || status.connecting;
});

Future<void> syncNow(MutationTarget target) {
  return refresh.run(target, (tx) async {
    final powersync = await tx.get(powerSyncInstanceProvider.future);
    final checkpoint = await powersync.requestCheckpoint();
    await checkpoint.waitForSync();
  });
}
