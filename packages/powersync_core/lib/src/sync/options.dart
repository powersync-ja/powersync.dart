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

  /// The client implementation to use.
  ///
  /// This allows switching between the existing [SyncClientImplementation.dart]
  /// implementation and a newer one ([SyncClientImplementation.rust]).
  ///
  /// Note that not setting this field to the default value is experimental.
  final SyncClientImplementation syncImplementation;

  const SyncOptions({
    this.crudThrottleTime,
    this.retryDelay,
    this.params,
    this.syncImplementation = SyncClientImplementation.dart,
  });
}

@internal
extension type ResolvedSyncOptions(SyncOptions source) {
  Duration get crudThrottleTime =>
      source.crudThrottleTime ?? const Duration(milliseconds: 10);

  Duration get retryDelay => source.retryDelay ?? const Duration(seconds: 5);

  Map<String, dynamic>? get params => source.params ?? const {};

  (ResolvedSyncOptions, bool) applyFrom(SyncOptions other) {
    final newOptions = SyncOptions(
      crudThrottleTime: other.crudThrottleTime ?? crudThrottleTime,
      retryDelay: other.retryDelay ?? retryDelay,
      params: other.params ?? params,
      syncImplementation: other.syncImplementation,
    );

    final didChange = !_mapEquality.equals(other.params, params) ||
        other.crudThrottleTime != crudThrottleTime ||
        other.retryDelay != retryDelay ||
        other.syncImplementation != source.syncImplementation;
    return (ResolvedSyncOptions(newOptions), didChange);
  }

  static const _mapEquality = MapEquality<String, dynamic>();
}

/// Supported sync client implementations.
///
/// Not using the default implementation (currently [dart], but this may change
/// in the future) is experimental.
@experimental
enum SyncClientImplementation {
  /// Decode and handle data received from the sync service in Dart.
  ///
  /// This is the default option.
  dart,

  /// An _experimental_ implementation of the sync client that is written in
  /// Rust and shared across the PowerSync SDKs.
  ///
  /// Since this client decodes sync lines in Rust instead of parsing them in
  /// Dart, it can be more performant than the the default [dart]
  /// implementation. Since this option has not seen as much real-world testing,
  /// it is marked as __experimental__ at the moment!
  @experimental
  rust,
}
