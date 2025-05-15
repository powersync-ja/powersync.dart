import 'package:collection/collection.dart';
import 'package:meta/meta.dart';

/// Options that affect how the sync client connects to the sync service.
final class SyncOptions {
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

  const SyncOptions({
    this.crudThrottleTime,
    this.retryDelay,
    this.params,
    this.syncImplementation = SyncClientImplementation.defaultClient,
  });
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
  Duration get crudThrottleTime =>
      source.crudThrottleTime ?? const Duration(milliseconds: 10);

  Duration get retryDelay => source.retryDelay ?? const Duration(seconds: 5);

  Map<String, dynamic> get params => source.params ?? const {};

  (ResolvedSyncOptions, bool) applyFrom(SyncOptions other) {
    final newOptions = SyncOptions(
      crudThrottleTime: other.crudThrottleTime ?? crudThrottleTime,
      retryDelay: other.retryDelay ?? retryDelay,
      params: other.params ?? params,
    );

    final didChange = !_mapEquality.equals(other.params, params) ||
        other.crudThrottleTime != crudThrottleTime ||
        other.retryDelay != retryDelay;
    return (ResolvedSyncOptions(newOptions), didChange);
  }

  static const _mapEquality = MapEquality<String, dynamic>();
}
