import 'dart:async';

import 'package:meta/meta.dart';

import '../connector.dart';
import '../database/powersync_database.dart';

@internal
abstract interface class InternalAuthenticator {
  /// Whether [postCheckpointRequest] might be implemented.
  ///
  /// When this is false, [postCheckpointRequest] is guaranteed to return
  /// `null`.
  bool get mightPostCheckpointRequests;

  /// Fetch or return cached credentials.
  Future<PowerSyncCredentials?> getCredentialsCached(Future<void> abortSignal);

  /// Ask the backend connector to fetch a new set of credentials.
  ///
  /// [invalidate] describes whether the current ([getCredentialsCached])
  /// credentials are already invalid, or whether this call is a pre-fetch.
  ///
  /// A call to [getCredentialsCached] after this future completes should return
  /// the same credentials.
  Future<PowerSyncCredentials?> prefetchCredentials({
    bool invalidate = false,
    required Future<void> abortSignal,
  });

  FutureOr<String?> postCheckpointRequest(
    String clientId,
    String checkpointRequestId,
    Future<void> abortSignal,
  );
}

@internal
abstract interface class InternalMutationUploader {
  Future<void> upload(Future<void> abortSignal);
}

/// A view over a backend connector that does not require a reference to the
/// PowerSync database.
final class InternalConnector {
  final InternalAuthenticator? authenticator;
  final InternalMutationUploader? uploader;

  InternalConnector(this.authenticator, this.uploader);

  factory InternalConnector.fromConnectRequest(
    ConnectRequest request,
    PowerSyncDatabase db,
  ) {
    if (request is PowerSyncBackendConnector) {
      return InternalConnector(
        LegacyAuthenticator(request),
        DatabaseBoundUploader(request, db),
      );
    } else if (request case InternalConnectRequest(
      :final endpoint,
      :final authenticator,
      :final uploader,
    )) {
      return InternalConnector(
        (endpoint != null && authenticator != null)
            ? SplitAuthenticator(endpoint, authenticator)
            : null,
        uploader != null ? DatabaseBoundUploader(uploader, db) : null,
      );
    } else {
      throw ArgumentError('Illegal external ConnectRequest implementation');
    }
  }
}

final class LegacyAuthenticator implements InternalAuthenticator {
  final PowerSyncBackendConnector connector;

  LegacyAuthenticator(this.connector);

  @override
  bool get mightPostCheckpointRequests {
    return connector is CustomCheckpointRequestConnector;
  }

  @override
  Future<PowerSyncCredentials?> getCredentialsCached(Future<void> _) async {
    return connector.getCredentialsCached();
  }

  @override
  Future<PowerSyncCredentials?> prefetchCredentials({
    bool invalidate = false,
    required Future<void> abortSignal,
  }) {
    if (invalidate) {
      connector.invalidateCredentials();
    }
    return connector.prefetchCredentials();
  }

  @override
  FutureOr<String?> postCheckpointRequest(
    String clientId,
    String checkpointRequestId,
    Future<void> abortSignal,
  ) {
    if (connector case final CustomCheckpointRequestConnector custom) {
      return custom.postCheckpointRequest(
        clientId,
        checkpointRequestId,
        abortSignal,
      );
    }

    return null;
  }
}

final class SplitAuthenticator implements InternalAuthenticator {
  final String _endpoint;
  final Authenticator _authenticator;

  SplitAuthenticator(this._endpoint, this._authenticator);

  @override
  bool get mightPostCheckpointRequests {
    return _authenticator is CustomCheckpointRequestConnector;
  }

  @override
  Future<PowerSyncCredentials?> getCredentialsCached(Future<void> abortSignal) {
    return _resolveCredentials(false, abortSignal);
  }

  @override
  FutureOr<String?> postCheckpointRequest(
    String clientId,
    String checkpointRequestId,
    Future<void> abortSignal,
  ) {
    if (_authenticator case final CustomCheckpointRequestConnector connector) {
      return connector.postCheckpointRequest(
        clientId,
        checkpointRequestId,
        abortSignal,
      );
    }

    return null;
  }

  @override
  Future<PowerSyncCredentials?> prefetchCredentials({
    bool invalidate = false,
    required Future<void> abortSignal,
  }) {
    return _resolveCredentials(invalidate, abortSignal);
  }

  Future<PowerSyncCredentials> _resolveCredentials(
    bool invalidateFirst,
    Future<void> abortSignal,
  ) async {
    if (invalidateFirst) {
      _authenticator.invalidateCredentials();
    }

    return PowerSyncCredentials(
      endpoint: _endpoint,
      token: await _authenticator.resolveCredentials(abortSignal),
    );
  }
}

final class DatabaseBoundUploader implements InternalMutationUploader {
  final MutationUploader _uploader;
  final PowerSyncDatabase _database;

  DatabaseBoundUploader(this._uploader, this._database);

  @override
  Future<void> upload(Future<void> abortSignal) =>
      _uploader.upload(_database, abortSignal);
}
