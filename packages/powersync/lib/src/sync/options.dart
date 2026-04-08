import 'package:collection/collection.dart';
import 'package:meta/meta.dart';

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

  const SyncOptions({
    this.crudThrottleTime,
    this.retryDelay,
    this.params,
    this.syncImplementation = SyncClientImplementation.defaultClient,
    this.includeDefaultStreams,
    this.appMetadata,
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
    );
  }
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
    return ResolvedSyncOptions((source ?? SyncOptions())._copyWith(
      crudThrottleTime: crudThrottleTime,
      retryDelay: retryDelay,
      params: params,
      appMetadata: appMetadata,
    ));
  }

  Map<String, String> get appMetadata => source.appMetadata ?? const {};

  Duration get crudThrottleTime =>
      source.crudThrottleTime ?? const Duration(milliseconds: 10);

  Duration get retryDelay => source.retryDelay ?? const Duration(seconds: 5);

  Map<String, dynamic> get params => source.params ?? const {};

  bool get includeDefaultStreams => source.includeDefaultStreams ?? true;

  (ResolvedSyncOptions, bool) applyFrom(SyncOptions other) {
    final newOptions = SyncOptions(
      crudThrottleTime: other.crudThrottleTime ?? crudThrottleTime,
      retryDelay: other.retryDelay ?? retryDelay,
      params: other.params ?? params,
      syncImplementation: other.syncImplementation,
      includeDefaultStreams:
          other.includeDefaultStreams ?? includeDefaultStreams,
      appMetadata: other.appMetadata ?? appMetadata,
    );

    final didChange = !_mapEquality.equals(newOptions.params, params) ||
        newOptions.crudThrottleTime != crudThrottleTime ||
        newOptions.retryDelay != retryDelay ||
        newOptions.syncImplementation != source.syncImplementation ||
        newOptions.includeDefaultStreams != includeDefaultStreams ||
        !_mapEquality.equals(newOptions.appMetadata, appMetadata);
    return (ResolvedSyncOptions(newOptions), didChange);
  }

  static const _mapEquality = MapEquality<String, dynamic>();
}
