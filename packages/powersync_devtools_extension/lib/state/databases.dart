import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:powersync/powersync.dart';
import 'package:vm_service/vm_service.dart';

import 'remote_database.dart';
import 'service.dart';

final class DatabaseReference {
  final int id;
  final String name;
  final String path;
  final PowerSyncCredentials? lastCredentials;

  final IsolateRef isolate;

  DatabaseReference({
    required this.id,
    required this.name,
    required this.path,
    this.lastCredentials,
    required this.isolate,
  });
}

final _databaseListChanged = StreamProvider.autoDispose<void>((ref) {
  return Stream.fromFuture(ref.watch(serviceProvider.future)).asyncExpand(
    (serviceProvider) => serviceProvider.onExtensionEvent.where((event) {
      return event.extensionKind == 'powersync:databases-changed';
    }),
  );
});

final databaseList = FutureProvider.autoDispose<List<DatabaseReference>>((
  ref,
) async {
  final service = await ref.watch(serviceProvider.future);
  final isolate = ref.watch(isolateProvider).value;
  ref.watch(_databaseListChanged);

  if (isolate == null) {
    return const [];
  }

  final list = await service.callServiceExtension(
    'ext.powersync.list',
    isolateId: isolate.id,
  );

  final databases = list.json!['databases'] as List;
  return [
    for (final serialized in databases.cast<Map<String, Object?>>())
      DatabaseReference(
        id: serialized['id'] as int,
        name: serialized['name'] as String,
        path: serialized['path'] as String,
        lastCredentials: switch (serialized['lastCredentials']) {
          null => null,
          final credentials as Map<String, Object?> => PowerSyncCredentials(
            endpoint: credentials['endpoint'] as String,
            token: credentials['token'] as String,
          ),
        },
        isolate: isolate,
      ),
  ];
});

final selectedDatabase =
    StateNotifierProvider.autoDispose<
      StateController<RemoteDatabase?>,
      RemoteDatabase?
    >((ref) {
      final service = ref.watch(serviceProvider);
      final controller = StateController<RemoteDatabase?>(null);

      if (service.value case final service?) {
        ref.listen(databaseList, (previous, next) {
          final databases = next.asData?.value ?? const [];

          if (databases.isEmpty) {
            controller.state = null;
          } else if (controller.state == null &&
              databases.every((e) => e.id != controller.state?.ref.id)) {
            controller.state = RemoteDatabase(databases.first, service);
          }
        }, fireImmediately: true);
      }

      return controller;
    });

final class DecodedCredentials {
  final PowerSyncCredentials original;

  final Map<String, Object?>? decodedClaims;
  final String userId;

  DecodedCredentials._(this.original, this.decodedClaims, this.userId);

  factory DecodedCredentials(PowerSyncCredentials original) {
    try {
      final [_, payload, _] = original.token.split('.');
      final decodedPayload =
          (json.fuse(utf8)).decode(base64.decode(payload))
              as Map<String, Object?>;
      final userId = decodedPayload['sub'].toString();

      return DecodedCredentials._(original, decodedPayload, userId);
    } on Object {
      // Couldn't parse, return bogus user id.
      return DecodedCredentials._(original, null, 'unknown');
    }
  }
}

/// The last recorded credentials for [selectedDatabase].
final lastCredentials = Provider<DecodedCredentials?>((ref) {
  final allDatabases = ref.watch(databaseList);
  final selected = ref.watch(selectedDatabase);
  if (selected == null) return null;

  for (final db in allDatabases.value ?? const <DatabaseReference>[]) {
    if (db.id == selected.ref.id) {
      return switch (db.lastCredentials) {
        null => null,
        final credentials => DecodedCredentials(credentials),
      };
    }
  }

  return null;
});
