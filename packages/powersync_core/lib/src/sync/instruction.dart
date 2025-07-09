import 'stream.dart';
import 'sync_status.dart';

/// An internal instruction emitted by the sync client in the core extension in
/// response to the Dart SDK passing sync data into the extension.
sealed class Instruction {
  factory Instruction.fromJson(Map<String, Object?> json) {
    return switch (json) {
      {'LogLine': final logLine} =>
        LogLine.fromJson(logLine as Map<String, Object?>),
      {'UpdateSyncStatus': final updateStatus} =>
        UpdateSyncStatus.fromJson(updateStatus as Map<String, Object?>),
      {'EstablishSyncStream': final establish} =>
        EstablishSyncStream.fromJson(establish as Map<String, Object?>),
      {'FetchCredentials': final creds} =>
        FetchCredentials.fromJson(creds as Map<String, Object?>),
      {'CloseSyncStream': _} => const CloseSyncStream(),
      {'FlushFileSystem': _} => const FlushFileSystem(),
      {'DidCompleteSync': _} => const DidCompleteSync(),
      _ => UnknownSyncInstruction(json)
    };
  }
}

final class LogLine implements Instruction {
  final String severity;
  final String line;

  LogLine({required this.severity, required this.line});

  factory LogLine.fromJson(Map<String, Object?> json) {
    return LogLine(
      severity: json['severity'] as String,
      line: json['line'] as String,
    );
  }
}

final class EstablishSyncStream implements Instruction {
  final Map<String, Object?> request;

  EstablishSyncStream(this.request);

  factory EstablishSyncStream.fromJson(Map<String, Object?> json) {
    return EstablishSyncStream(json['request'] as Map<String, Object?>);
  }
}

final class UpdateSyncStatus implements Instruction {
  final CoreSyncStatus status;

  UpdateSyncStatus({required this.status});

  factory UpdateSyncStatus.fromJson(Map<String, Object?> json) {
    return UpdateSyncStatus(
        status:
            CoreSyncStatus.fromJson(json['status'] as Map<String, Object?>));
  }
}

final class CoreSyncStatus {
  final bool connected;
  final bool connecting;
  final List<SyncPriorityStatus> priorityStatus;
  final DownloadProgress? downloading;
  final List<CoreActiveStreamSubscription>? streams;

  CoreSyncStatus({
    required this.connected,
    required this.connecting,
    required this.priorityStatus,
    required this.downloading,
    required this.streams,
  });

  factory CoreSyncStatus.fromJson(Map<String, Object?> json) {
    return CoreSyncStatus(
      connected: json['connected'] as bool,
      connecting: json['connecting'] as bool,
      priorityStatus: [
        for (final entry in json['priority_status'] as List)
          _priorityStatusFromJson(entry as Map<String, Object?>)
      ],
      downloading: switch (json['downloading']) {
        null => null,
        final raw as Map<String, Object?> => DownloadProgress.fromJson(raw),
      },
      streams: (json['stream'] as List<Object?>?)
          ?.map((e) =>
              CoreActiveStreamSubscription.fromJson(e as Map<String, Object?>))
          .toList(),
    );
  }

  static SyncPriorityStatus _priorityStatusFromJson(Map<String, Object?> json) {
    return (
      priority: BucketPriority(json['priority'] as int),
      hasSynced: json['has_synced'] as bool?,
      lastSyncedAt: switch (json['last_synced_at']) {
        null => null,
        final lastSyncedAt as int =>
          DateTime.fromMillisecondsSinceEpoch(lastSyncedAt * 1000),
      },
    );
  }
}

final class DownloadProgress {
  final Map<String, BucketProgress> buckets;

  DownloadProgress(this.buckets);

  factory DownloadProgress.fromJson(Map<String, Object?> line) {
    final rawBuckets = line['buckets'] as Map<String, Object?>;

    return DownloadProgress(rawBuckets.map((k, v) {
      return MapEntry(
        k,
        _bucketProgressFromJson(v as Map<String, Object?>),
      );
    }));
  }

  static BucketProgress _bucketProgressFromJson(Map<String, Object?> json) {
    return (
      priority: BucketPriority(json['priority'] as int),
      atLast: json['at_last'] as int,
      sinceLast: json['since_last'] as int,
      targetCount: json['target_count'] as int,
    );
  }
}

final class FetchCredentials implements Instruction {
  final bool didExpire;

  FetchCredentials(this.didExpire);

  factory FetchCredentials.fromJson(Map<String, Object?> line) {
    return FetchCredentials(line['did_expire'] as bool);
  }
}

final class CloseSyncStream implements Instruction {
  const CloseSyncStream();
}

final class FlushFileSystem implements Instruction {
  const FlushFileSystem();
}

final class DidCompleteSync implements Instruction {
  const DidCompleteSync();
}

final class UnknownSyncInstruction implements Instruction {
  final Map<String, Object?> source;

  UnknownSyncInstruction(this.source);
}
