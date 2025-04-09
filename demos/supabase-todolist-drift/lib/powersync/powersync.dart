import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'package:powersync/powersync.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:stream_transform/stream_transform.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../supabase.dart';
import 'connector.dart';
import 'schema.dart';

part 'powersync.g.dart';

@Riverpod(keepAlive: true)
Future<PowerSyncDatabase> powerSyncInstance(Ref ref) async {
  final db = PowerSyncDatabase(
    schema: schema,
    path: await _getDatabasePath(),
    logger: attachedLogger,
  );
  await db.initialize();

  SupabaseConnector? currentConnector;
  if (ref.read(sessionProvider).value != null) {
    currentConnector = SupabaseConnector();
    db.connect(connector: currentConnector);
  }

  final instance = Supabase.instance.client.auth;
  final sub = instance.onAuthStateChange.listen((data) async {
    final event = data.event;
    if (event == AuthChangeEvent.signedIn) {
      currentConnector = SupabaseConnector();
      db.connect(connector: currentConnector!);
    } else if (event == AuthChangeEvent.signedOut) {
      currentConnector = null;
      await db.disconnect();
    } else if (event == AuthChangeEvent.tokenRefreshed) {
      currentConnector?.prefetchCredentials();
    }
  });
  ref.onDispose(sub.cancel);
  ref.onDispose(db.close);

  return db;
}

final _syncStatusInternal = StreamProvider((ref) {
  return Stream.fromFuture(
    ref.watch(powerSyncInstanceProvider.future),
  ).asyncExpand((db) => db.statusStream).startWith(const SyncStatus());
});

final syncStatus = Provider((ref) {
  return ref.watch(_syncStatusInternal).value ?? const SyncStatus();
});

@riverpod
bool didCompleteSync(Ref ref, [BucketPriority? priority]) {
  final status = ref.watch(syncStatus);
  if (priority != null) {
    return status.statusForPriority(priority).hasSynced ?? false;
  } else {
    return status.hasSynced ?? false;
  }
}

Future<String> _getDatabasePath() async {
  const dbFilename = 'powersync-demo.db';
  // getApplicationSupportDirectory is not supported on Web
  if (kIsWeb) {
    return dbFilename;
  }
  final dir = await getApplicationSupportDirectory();
  return join(dir.path, dbFilename);
}
