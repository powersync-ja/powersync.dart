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

/// The PowerSync SDK offers two different implementations for receiving sync
/// lines: One handling most logic in Dart, and a newer one offloading that work
/// to the native PowerSync extension.
enum SyncClientImplementation {
  /// A sync implementation that decodes and handles sync lines in Dart.
  @Deprecated(
    "Don't use SyncClientImplementation.dart directly, "
    "use SyncClientImplementation.defaultClient instead.",
  )
  dart,

  /// An experimental sync implementation that parses and handles sync lines in
  /// the native PowerSync core extensions.
  ///
  /// This implementation can be more performant than the Dart implementation,
  /// and supports receiving sync lines in a more efficient format.
  ///
  /// Note that this option is currently experimental.
  @experimental
  rust;

  /// The default sync client implementation to use.
  // ignore: deprecated_member_use_from_same_package
  static const defaultClient = dart;
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
    );

    final didChange = !_mapEquality.equals(newOptions.params, params) ||
        newOptions.crudThrottleTime != crudThrottleTime ||
        newOptions.retryDelay != retryDelay ||
        newOptions.syncImplementation != source.syncImplementation ||
        newOptions.includeDefaultStreams != includeDefaultStreams;
    return (ResolvedSyncOptions(newOptions), didChange);
  }

  static const _mapEquality = MapEquality<String, dynamic>();
}
