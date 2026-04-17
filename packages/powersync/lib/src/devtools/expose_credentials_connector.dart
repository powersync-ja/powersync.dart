import 'package:powersync/src/database/powersync_database.dart';

import '../connector.dart';
import 'devtools.dart';

/// A PowerSync backend connector that logs credentials over the VM service
/// protocol, allowing our DevTools extension to display the current token.
final class ExposeCredentialsConnector extends PowerSyncBackendConnector {
  final PowerSyncDatabase database;
  final PowerSyncBackendConnector inner;

  ExposeCredentialsConnector(this.inner, this.database);

  @override
  Future<PowerSyncCredentials?> fetchCredentials() async {
    final credentials = await inner.fetchCredentials();
    if (ExposedPowerSyncDatabase.byDatabase[database] case final exposed?) {
      exposed.lastCredentials = credentials;
      ExposedPowerSyncDatabase.postChangeEvent();
    }

    return credentials;
  }

  @override
  Future<void> uploadData(PowerSyncDatabase database) {
    return inner.uploadData(database);
  }
}
