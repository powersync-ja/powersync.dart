/// Dart mirror of `shapes.ts` (the data shapes of the Diagnostics Protocol).
///
/// Every value that crosses between the Dart SDK integration and the diagnostics UI is one of
/// these. Conventions match the source file: every time is epoch milliseconds; a value that does
/// not apply is `null`.
///
/// Types read from a JS caller (method arguments) only expose getters. Types this integration
/// builds to hand back to JS (return values, event payloads) expose an `external factory` as well.
library;

import 'dart:js_interop';

extension type DiagnosticsEvent._(JSObject _) implements JSObject {
  external factory DiagnosticsEvent({
    required JSString type,
    required JSAny payload,
  });

  factory DiagnosticsEvent.uploadQueue(UploadQueueState payload) {
    return DiagnosticsEvent(type: 'uploadQueue'.toJS, payload: payload);
  }

  factory DiagnosticsEvent.buckets(JSArray<BucketState> buckets) {
    return DiagnosticsEvent(type: 'buckets'.toJS, payload: buckets);
  }

  factory DiagnosticsEvent.status(SyncState status) {
    return DiagnosticsEvent(type: 'status'.toJS, payload: status);
  }

  factory DiagnosticsEvent.streams(JSArray<StreamState> streams) {
    return DiagnosticsEvent(type: 'v'.toJS, payload: streams);
  }
}

/// Disposes a subscription or listener.
typedef Unsubscribe = JSFunction<void Function()>;

// --- queries ---

extension type QueryParams(JSObject _) implements JSObject {
  external JSString get sql;
  external JSArray? get params;
}

/// A serialized SQL result set.
extension type QueryResult._(JSObject _) implements JSObject {
  external factory QueryResult({
    /// Column names, in order.
    required JSArray<JSString> columns,

    /// One object per row, keyed by column name.
    required JSArray<JSObject> rows,
    required int rowCount,
  });

  external JSArray<JSString> get columns;
  external JSArray<JSObject> get rows;
  external int get rowCount;
}

// --- sync status ---

/// Download progress expressed in operation counts.
extension type ProgressState._(JSObject _) implements JSObject {
  external factory ProgressState({
    required int downloadedOperations,
    required int totalOperations,

    /// `0` to `1`.
    required double downloadedFraction,
  });

  external int get downloadedOperations;
  external int get totalOperations;
  external double get downloadedFraction;
}

/// Sync state for a single bucket priority level.
extension type PriorityState._(JSObject _) implements JSObject {
  external factory PriorityState({
    required int priority,

    /// Epoch milliseconds, or null if never synced at this priority.
    required int? lastSyncedAt,
    required bool? hasSynced,
  });

  external int get priority;
  external int? get lastSyncedAt;
  external bool? get hasSynced;
}

/// A point-in-time, serialized view of the client's sync status.
extension type SyncState._(JSObject _) implements JSObject {
  external factory SyncState({
    required bool connected,
    required bool connecting,
    required bool downloading,
    required bool uploading,
    required bool? hasSynced,

    /// Epoch milliseconds of the last completed sync, or null.
    required int? lastSyncedAt,
    required ProgressState? downloadProgress,
    required JSArray<PriorityState> priorities,
    required String? downloadError,
    required String? uploadError,
    required String message,
  });

  external bool get connected;
  external bool get connecting;
  external bool get downloading;
  external bool get uploading;
  external bool? get hasSynced;
  external int? get lastSyncedAt;
  external ProgressState? get downloadProgress;
  external JSArray<PriorityState> get priorities;
  external String? get downloadError;
  external String? get uploadError;
  external String get message;
}

/// State for a single sync stream.
extension type StreamState._(JSObject _) implements JSObject {
  external factory StreamState({
    required String? name,
    required int? priority,

    /// True while this stream is actively downloading.
    required bool active,

    /// Included by default because the stream sets `auto_subscribe`.
    required bool autoSubscribed,

    /// Subscribed to explicitly at runtime.
    required bool explicitlySubscribed,
    required ProgressState? progress,
    required JSObject? params,

    /// Epoch milliseconds at which the subscription expires (TTL), or null.
    required int? expiresAt,
    required bool hasSynced,

    /// Epoch milliseconds of the last sync for this stream, or null.
    required int? lastSyncedAt,
  });

  external String? get name;
  external int? get priority;
  external bool get active;
  external bool get autoSubscribed;
  external bool get explicitlySubscribed;
  external ProgressState? get progress;
  external JSObject? get params;
  external int? get expiresAt;
  external bool get hasSynced;
  external int? get lastSyncedAt;
}

// --- buckets / upload queue / logs ---

/// Per-bucket download stats, read from the core `ps_buckets` table.
extension type BucketState._(JSObject _) implements JSObject {
  external factory BucketState({
    required String name,

    /// `count_at_last + count_since_last` from `ps_buckets`.
    required int downloadedOperations,

    /// Total operations for the current checkpoint, or null when the core diagnostics stream is off.
    required int? totalOperations,

    /// Downloaded payload size in bytes, or null on cores that don't track it.
    required int? downloadedSize,
    required String? lastOp,
    required bool downloading,
  });

  external String get name;
  external int get downloadedOperations;
  external int? get totalOperations;
  external int? get downloadedSize;
  external String? get lastOp;
  external bool get downloading;
}

/// Pending upload (CRUD) queue state. Recoverable in any SDK with SQL against `ps_crud`.
extension type UploadQueueState._(JSObject _) implements JSObject {
  external factory UploadQueueState({
    required int count,

    /// Byte size, or null when not computed.
    required int? size,
  });

  external int get count;
  external int? get size;
}

/// A captured client log line.
extension type LogRecord._(JSObject _) implements JSObject {
  external factory LogRecord({
    /// Epoch milliseconds.
    required int timestamp,

    /// One of `trace`, `debug`, `info`, `warn`, `error`.
    required String level,
    required String message,
    JSArray? args,
  });

  external int get timestamp;
  external String get level;
  external String get message;
  external JSArray? get args;
}

// --- connection info ---

/// Connection metadata for the attached client.
extension type ProtocolInfo._(JSObject _) implements JSObject {
  external factory ProtocolInfo({
    /// The PowerSync service endpoint.
    required String? endpoint,

    /// Derive from the token subject when the SDK does not expose it.
    required String? userId,

    /// The PowerSync client id.
    required String? clientId,

    /// For example `http` or `websocket`.
    required String? connectionMethod,

    /// Client parameters sent on connect.
    required JSObject? params,
    required bool connected,

    /// Core extension version, from `SELECT powersync_rs_version()`.
    required String? sqliteCoreVersion,

    /// A label for the SDK behind the integration (e.g. `@powersync/web`, `powersync` (Dart)); null when unknown.
    required String? sdk,
  });

  external String? get endpoint;
  external String? get userId;
  external String? get clientId;
  external String? get connectionMethod;
  external JSObject? get params;
  external bool get connected;
  external String? get sqliteCoreVersion;
  external String? get sdk;
}

// --- schema ---

// --- core diagnostics events ---

/// A single bucket's updated target count, as reported by [CoreDiagnosticsEvent.bucketStateChange].
extension type BucketStateChangeProgress._(JSObject _) implements JSObject {
  external factory BucketStateChangeProgress({
    @JS('target_count') required int targetCount,
  });

  @JS('target_count')
  external int get targetCount;
}

extension type BucketStateChangeEntry._(JSObject _) implements JSObject {
  external factory BucketStateChangeEntry({
    required String name,
    required BucketStateChangeProgress progress,
  });

  external String get name;
  external BucketStateChangeProgress get progress;
}

extension type BucketStateChangePayload._(JSObject _) implements JSObject {
  external factory BucketStateChangePayload({
    required JSArray<BucketStateChangeEntry> changes,
    bool? incremental,
  });

  external JSArray<BucketStateChangeEntry> get changes;
  external bool? get incremental;
}

/// The slice of the SQLite core's diagnostics event stream the tool consumes: per-bucket target
/// totals (`target_count`) and inferred schema changes. Emitted by the core when the client connects
/// with diagnostics enabled.
///
/// A tagged union represented as an object with exactly one of [bucketStateChange] or
/// [schemaChange] set, matching the JSON the core emits.
extension type CoreDiagnosticsEvent._raw(JSObject _) implements JSObject {
  external factory CoreDiagnosticsEvent._({
    @JS('BucketStateChange') BucketStateChangePayload? bucketStateChange,
    @JS('SchemaChange') JSAny? schemaChange,
  });

  factory CoreDiagnosticsEvent.bucketStateChange(
    BucketStateChangePayload value,
  ) => CoreDiagnosticsEvent._(bucketStateChange: value);

  factory CoreDiagnosticsEvent.schemaChange(JSAny value) =>
      CoreDiagnosticsEvent._(schemaChange: value);

  @JS('BucketStateChange')
  external BucketStateChangePayload? get bucketStateChange;
  @JS('SchemaChange')
  external JSAny? get schemaChange;
}

// --- actions ---

/// Control actions the tool can invoke on the live client.
enum ActionName {
  /// Disconnect, then connect again with the last connector.
  reconnect,

  /// Disconnect the client.
  disconnect,

  /// Clear the local database, then connect again.
  clearData,

  /// Confirm the client is caught up. Needs checkpoint requests enabled.
  requestCheckpoint,

  /// Subscribe to a sync stream ([StreamActionArgs]). `ttl` defaults to `0`.
  subscribeStream,

  /// Release a subscription created with [subscribeStream].
  unsubscribeStream,
}

/// Arguments for `subscribeStream` / `unsubscribeStream`.
extension type StreamActionArgs(JSObject _) implements JSObject {
  external String get name;
  external JSObject? get params;

  /// Seconds. Defaults to 0 so a forgotten debug subscription is evicted once released.
  external int? get ttl;

  /// `0`, `1`, `2` or `3`.
  external int? get priority;
}

/// A control action and its arguments (only the stream actions take any).
extension type ActionRequest(JSObject _) implements JSObject {
  /// The name of an [ActionName] member.
  external String get action;
  external StreamActionArgs? get args;
}

@anonymous
extension type DiagnosticsSource._(JSObject _) implements JSObject {
  external factory DiagnosticsSource({required String id, required String sdk});

  external String get id;
  external String get sdk;
}
