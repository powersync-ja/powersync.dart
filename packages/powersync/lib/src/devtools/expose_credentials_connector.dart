import 'dart:async';

import 'package:powersync/src/database/powersync_database.dart';

import '../connector.dart';
import '../sync/internal_connector.dart';
import 'devtools.dart';

/// A wrapping authenticator implementation that logs credentials over the VM
/// service protocol, allowing our DevTools extension to display the current token.
final class ExposeCredentialsConnector implements InternalAuthenticator {
  final PowerSyncDatabase database;
  final InternalAuthenticator inner;

  ExposeCredentialsConnector(this.inner, this.database);

  PowerSyncCredentials? _exposeCredentials(PowerSyncCredentials? credentials) {
    if (ExposedPowerSyncDatabase.byDatabase[database] case final exposed?) {
      exposed.lastCredentials = credentials;
      ExposedPowerSyncDatabase.postChangeEvent();
    }

    return credentials;
  }

  @override
  bool get mightPostCheckpointRequests => inner.mightPostCheckpointRequests;

  @override
  Future<PowerSyncCredentials?> getCredentialsCached(Future<void> abortSignal) {
    return inner.getCredentialsCached(abortSignal).then(_exposeCredentials);
  }

  @override
  Future<PowerSyncCredentials?> prefetchCredentials({
    bool invalidate = false,
    required Future<void> abortSignal,
  }) {
    return inner
        .prefetchCredentials(invalidate: invalidate, abortSignal: abortSignal)
        .then(_exposeCredentials);
  }

  @override
  FutureOr<String?> postCheckpointRequest(
    String clientId,
    String checkpointRequestId,
    Future<void> abortSignal,
  ) => inner.postCheckpointRequest(clientId, checkpointRequestId, abortSignal);
}
