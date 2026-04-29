@internal
library;

import 'dart:developer' as dev;
import 'package:meta/meta.dart';

import '../connector.dart';
import '../database/powersync_database.dart';
import 'extension.dart';

// We want to avoid including this code for release-mode builds, since it's only
// relevant for development tooling. This matches the definition of Flutter's
// kReleaseMode: https://api.flutter.dev/flutter/foundation/kReleaseMode-constant.html
const _releaseMode = bool.fromEnvironment('dart.vm.product');
const enable = !_releaseMode;

void postEvent(String type, Map<String, Object?> data) {
  dev.postEvent('powersync:$type', data);
}

/// A PowerSync database made accessible to DevTools over a `dart:developer` IPC
/// protocol.
final class ExposedPowerSyncDatabase {
  final PowerSyncDatabase database;
  final int id;

  PowerSyncCredentials? lastCredentials;

  ExposedPowerSyncDatabase(this.database) : id = _nextId++ {
    byDatabase[database] = this;
    byId[id] = this;
  }

  static int _nextId = 0;

  static Map<int, ExposedPowerSyncDatabase> byId = {};

  /// Weak map from PowerSync databases to their [ExposedPowerSyncDatabase]
  /// instance.
  static final Expando<ExposedPowerSyncDatabase> byDatabase = Expando();

  static void postChangeEvent() {
    postEvent('databases-changed', {});
  }
}

void handleCreated(PowerSyncDatabase database) {
  if (enable) {
    ExposedPowerSyncDatabase(database);
    PowerSyncDevToolsExtension.registerIfNeeded();
    ExposedPowerSyncDatabase.postChangeEvent();
  }
}

void handleClosed(PowerSyncDatabase database) {
  if (enable) {
    if (ExposedPowerSyncDatabase.byDatabase[database] case final tracked?) {
      ExposedPowerSyncDatabase.byId.remove(tracked.id);
      ExposedPowerSyncDatabase.byDatabase[database] = null;
    }

    ExposedPowerSyncDatabase.postChangeEvent();
  }
}
