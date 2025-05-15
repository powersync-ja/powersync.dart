import 'package:meta/meta.dart';

import '../connector.dart';
import '../database/powersync_database.dart';

/// A view over a backend connector that does not require a reference to the
/// PowerSync database.
@internal
abstract interface class InternalConnector {
  /// Fetch or return cached credentials.
  Future<PowerSyncCredentials?> getCredentialsCached();

  /// Ask the backend connector to fetch a new set of credentials.
  ///
  /// [invalidate] describes whether the current ([getCredentialsCached])
  /// credentials are already invalid, or whether this call is a pre-fetch.
  ///
  /// A call to [getCredentialsCached] after this future completes should return
  /// the same credentials.
  Future<PowerSyncCredentials?> prefetchCredentials({bool invalidate = false});

  /// Requests the connector to upload a crud batch to the backend.
  Future<void> uploadCrud();

  const factory InternalConnector({
    required Future<PowerSyncCredentials?> Function() getCredentialsCached,
    required Future<PowerSyncCredentials?> Function({required bool invalidate})
        prefetchCredentials,
    required Future<void> Function() uploadCrud,
  }) = _CallbackConnector;

  factory InternalConnector.wrap(
      PowerSyncBackendConnector connector, PowerSyncDatabase db) {
    return _WrapConnector(connector, db);
  }
}

final class _WrapConnector implements InternalConnector {
  final PowerSyncBackendConnector connector;
  final PowerSyncDatabase database;

  _WrapConnector(this.connector, this.database);

  @override
  Future<PowerSyncCredentials?> getCredentialsCached() async {
    return connector.getCredentialsCached();
  }

  @override
  Future<PowerSyncCredentials?> prefetchCredentials({bool invalidate = false}) {
    if (invalidate) {
      connector.invalidateCredentials();
    }
    return connector.prefetchCredentials();
  }

  @override
  Future<void> uploadCrud() {
    return connector.uploadData(database);
  }
}

final class _CallbackConnector implements InternalConnector {
  final Future<PowerSyncCredentials?> Function() _getCredentialsCached;
  final Future<PowerSyncCredentials?> Function({required bool invalidate})
      _prefetchCredentials;
  final Future<void> Function() _uploadCrud;

  const _CallbackConnector({
    required Future<PowerSyncCredentials?> Function() getCredentialsCached,
    required Future<PowerSyncCredentials?> Function({required bool invalidate})
        prefetchCredentials,
    required Future<void> Function() uploadCrud,
  })  : _getCredentialsCached = getCredentialsCached,
        _prefetchCredentials = prefetchCredentials,
        _uploadCrud = uploadCrud;

  @override
  Future<PowerSyncCredentials?> getCredentialsCached() {
    return _getCredentialsCached();
  }

  @override
  Future<PowerSyncCredentials?> prefetchCredentials({bool invalidate = false}) {
    return _prefetchCredentials(invalidate: invalidate);
  }

  @override
  Future<void> uploadCrud() {
    return _uploadCrud();
  }
}
