import 'package:collection/collection.dart';
import 'package:http/http.dart';
import 'package:meta/meta.dart';

/// The signature of a function creating a http [Client] to use by the PowerSync
/// SDK.
///
/// PowerSync will use [Client.new] by default, but a custom factory can be used
/// as [SyncOptions.httpClient]. This allows transforming requests and
/// responses, e.g. to add additional headers or allow custom TLS certificates.
///
/// On native platforms, these functions are sent across send ports (and thus
/// must not capture non-sendable state).
typedef HttpClientFactory = Client Function();

/// Options that affect how the sync client connects to the sync service.
final class SyncOptions {
  /// A map of application metadata that is passed to the PowerSync service.
  ///
  /// Application metadata that will be displayed in PowerSync service logs.
  final Map<String, String>? appMetadata;

  /// A JSON object that is passed to the sync service and forwarded to sync
  /// rules.
  ///
  /// These [parameters](https://docs.powersync.com/usage/sync-rules/advanced-topics/client-parameters)
  /// can be used in sync rules to deliver different data to different clients
  /// depending on the values used in [params].
  final Map<String, dynamic>? params;

  /// A throttle to apply when listening for local database changes before
  /// scheduling them for uploads.
  ///
  /// The throttle is applied to avoid frequent tiny writes in favor of more
  /// efficient batched uploads. When set to null, PowerSync defaults to a
  /// throtle duration of 10 milliseconds.
  final Duration? crudThrottleTime;

  /// How long PowerSync should wait before reconnecting after an error.
  ///
  /// When set to null, PowerSync defaults to a delay of 5 seconds.
  final Duration? retryDelay;

  /// The [SyncClientImplementation] to use.
  final SyncClientImplementation syncImplementation;

  /// Whether streams that have been defined with `auto_subscribe: true` should
  /// be synced when they don't have an explicit subscription.
  ///
  /// This is enabled by default.
  final bool? includeDefaultStreams;

  /// A function to create http clients used by the PowerSync SDK.
  ///
  /// Custom clients can be used to configure TLS options, inject additional
  /// headers, or otherwise customize networking.
  ///
  /// Note that this function is sent across isolates on native platforms.
  final HttpClientFactory? httpClient;

  /// The [CheckpointMode] used to request checkpoints from the PowerSync
  /// service.
  ///
  /// Checkpoint requests are used to request a confirmation after uploading
  /// local mutations. This defaults to [CheckpointMode.legacy], but can be set
  /// to [CheckpointMode.requests] when PowerSync service version 1.24.0 or
  /// later is used.
  final CheckpointMode? checkpointMode;

  const SyncOptions({
    this.crudThrottleTime,
    this.retryDelay,
    this.params,
    this.syncImplementation = SyncClientImplementation.defaultClient,
    this.includeDefaultStreams,
    this.appMetadata,
    this.httpClient,
    this.checkpointMode,
  });

  SyncOptions _copyWith({
    Duration? crudThrottleTime,
    Duration? retryDelay,
    Map<String, dynamic>? params,
    Map<String, String>? appMetadata,
  }) {
    return SyncOptions(
      crudThrottleTime: crudThrottleTime ?? this.crudThrottleTime,
      retryDelay: retryDelay,
      params: params ?? this.params,
      syncImplementation: syncImplementation,
      includeDefaultStreams: includeDefaultStreams,
      appMetadata: appMetadata ?? this.appMetadata,
      httpClient: httpClient,
      checkpointMode: checkpointMode,
    );
  }
}

/// The mechanism to reqeuest checkpoints from the PowerSync service.
///
/// Checkpoint requests are used after a client uploads local mutations. The
/// PowerSync service later references them in downloaded data, allowing the SDK
/// to assume that uploaded data has been synced down again.
///
/// There are two ways to send checkpoint requests: A legacy (but default and
/// stable) format supported by all PowerSync service versions, and a newer
/// ([CheckpointMode.requests]) method which is only available from PowerSync
/// service version 1.24.0 or later.
final class CheckpointMode {
  const CheckpointMode._();

  /// Uses an older mechanism for requesting checkpoints supported by all
  /// PowerSync service versions.
  const factory CheckpointMode.legacy() = LegacyCheckpointMode;

  /// Uses a newer endpoint supported from PowerSync service 1.24.0 or later.
  /// This method is more efficient and has better support for switching users
  /// in your app.
  ///
  /// Requested checkpoints are retried automatically, using the configured
  /// [retryDelay] (which defaults to 10 seconds, but can also be configured to
  /// use a longer retry interval).
  @experimental
  factory CheckpointMode.requests({Duration retryDelay}) =
      RequestsCheckpointMode;
}

@internal
final class LegacyCheckpointMode extends CheckpointMode {
  const LegacyCheckpointMode() : super._();

  @override
  bool operator ==(Object other) => other is LegacyCheckpointMode;

  @override
  int get hashCode => 'legacy'.hashCode;
}

final class RequestsCheckpointMode extends CheckpointMode {
  final Duration retryDelay;

  RequestsCheckpointMode({this.retryDelay = _defaultRetryDelay}) : super._() {
    if (retryDelay < _minimumRetryDelay) {
      throw ArgumentError.value(
        retryDelay,
        'retryDelay',
        'Must be at least $_minimumRetryDelay',
      );
    }
  }

  @visibleForTesting
  const RequestsCheckpointMode.unverifiedDuration(this.retryDelay) : super._();

  @override
  bool operator ==(Object other) =>
      other is RequestsCheckpointMode && other.retryDelay == retryDelay;

  @override
  int get hashCode => retryDelay.hashCode;

  static const _minimumRetryDelay = Duration(seconds: 10);
  static const _defaultRetryDelay = _minimumRetryDelay;
}

/// Older versions of the PowerSync SDK offered two sync client implementations.
///
/// The older Dart-based client has been removed in favor of a Rust
/// implementation shared across all PowerSync SDKs, so this enum is no longer
/// functional.
enum SyncClientImplementation {
  /// A PowerSync client where the state machine is implemented in Rust and Dart
  /// is only used for networking.
  ///
  /// This is the only client implementation supported by the current version of
  /// the Dart SDK.
  rust;

  /// The default sync client implementation to use.
  static const defaultClient = rust;
}

@internal
extension type ResolvedSyncOptions(SyncOptions source) {
  factory ResolvedSyncOptions.resolve(
    SyncOptions? source, {
    Duration? crudThrottleTime,
    Duration? retryDelay,
    Map<String, dynamic>? params,
    Map<String, String>? appMetadata,
  }) {
    return ResolvedSyncOptions(
      (source ?? SyncOptions())._copyWith(
        crudThrottleTime: crudThrottleTime,
        retryDelay: retryDelay,
        params: params,
        appMetadata: appMetadata,
      ),
    );
  }

  Map<String, String> get appMetadata => source.appMetadata ?? const {};

  Duration get crudThrottleTime =>
      source.crudThrottleTime ?? const Duration(milliseconds: 10);

  Duration get retryDelay => source.retryDelay ?? const Duration(seconds: 5);

  Map<String, dynamic> get params => source.params ?? const {};

  bool get includeDefaultStreams => source.includeDefaultStreams ?? true;

  CheckpointMode get checkpointMode =>
      source.checkpointMode ?? const CheckpointMode.legacy();

  Client createHttpClient() => source.httpClient?.call() ?? Client();

  (ResolvedSyncOptions, bool) applyFrom(SyncOptions other) {
    final newOptions = SyncOptions(
      crudThrottleTime: other.crudThrottleTime ?? crudThrottleTime,
      retryDelay: other.retryDelay ?? retryDelay,
      params: other.params ?? params,
      syncImplementation: other.syncImplementation,
      includeDefaultStreams:
          other.includeDefaultStreams ?? includeDefaultStreams,
      appMetadata: other.appMetadata ?? appMetadata,
      httpClient: other.httpClient ?? source.httpClient,
      checkpointMode: other.checkpointMode ?? checkpointMode,
    );

    final didChange =
        !_mapEquality.equals(newOptions.params, params) ||
        newOptions.crudThrottleTime != crudThrottleTime ||
        newOptions.retryDelay != retryDelay ||
        newOptions.syncImplementation != source.syncImplementation ||
        newOptions.includeDefaultStreams != includeDefaultStreams ||
        !_mapEquality.equals(newOptions.appMetadata, appMetadata) ||
        newOptions.checkpointMode != checkpointMode;
    return (ResolvedSyncOptions(newOptions), didChange);
  }

  static const _mapEquality = MapEquality<String, dynamic>();
}
