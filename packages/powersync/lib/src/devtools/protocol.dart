import 'dart:convert';
import 'dart:typed_data';

import '../sync/instruction.dart';
import '../sync/stream.dart';
import '../sync/sync_status.dart';

/// Encodes a Dart value that can appear as a SQL parameter or result to be
/// JSON serializable.
Object? encodeSqlValue(Object? value) {
  return switch (value) {
    final Uint8List binary => {'binary': base64.encode(binary)},
    _ => value,
  };
}

Object? decodeSqlValue(Object? value) {
  return switch (value) {
    {'binary': final String binary} => base64.decode(binary),
    _ => value,
  };
}

Object? serializeSyncStatus(SyncStatus status) {
  return {
    'connected': status.connected,
    'connecting': status.connecting,
    'downloading': status.downloading,
    'downloadProgress': switch (status.downloadProgress) {
      null => null,
      final progress => DownloadProgress(
              InternalSyncDownloadProgress.ofPublic(progress).buckets)
          .toJson()
    },
    'uploading': status.uploading,
    'lastSyncedAt': status.lastSyncedAt?.millisecondsSinceEpoch,
    'hasSynced': status.hasSynced,
    'uploadError': status.uploadError?.toString(),
    'downloadError': status.downloadError?.toString(),
    'priorityStatusEntries': [
      for (final entry in status.priorityStatusEntries)
        {
          'priority': entry.priority.priorityNumber,
          'lastSyncedAt': entry.lastSyncedAt?.millisecondsSinceEpoch,
          'hasSynced': entry.hasSynced,
        }
    ],
    'internalSubscriptions':
        status.internalSubscriptions?.map((s) => s.toJson()).toList(),
  };
}

SyncStatus deserializeSyncStatus(Map<String, Object?> serialized) {
  DateTime? readDateTime(Object? timestamp) {
    return timestamp == null
        ? null
        : DateTime.fromMillisecondsSinceEpoch(timestamp as int);
  }

  return SyncStatus(
    connected: serialized['connected'] as bool,
    connecting: serialized['connecting'] as bool,
    downloading: serialized['downloading'] as bool,
    downloadProgress: switch (serialized['downloadProgress']) {
      null => null,
      final downloadProgress => InternalSyncDownloadProgress(
              DownloadProgress.fromJson(
                      downloadProgress as Map<String, Object?>)
                  .buckets)
          .asSyncDownloadProgress
    },
    uploading: serialized['uploading'] as bool,
    lastSyncedAt: readDateTime(serialized['lastSyncedAt'] as int?),
    hasSynced: serialized['hasSynced'] as bool?,
    uploadError: serialized['uploadError'],
    downloadError: serialized['downloadError'],
    priorityStatusEntries: [
      for (final entry in (serialized['priorityStatusEntries'] as List)
          .cast<Map<String, Object?>>())
        (
          priority: StreamPriority(entry['priority'] as int),
          lastSyncedAt: readDateTime(entry['lastSyncedAt']),
          hasSynced: entry['hasSynced'] as bool?
        )
    ],
    streamSubscriptions: switch (serialized['internalSubscriptions']) {
      final List<Object?> entries => entries
          .map((e) =>
              CoreActiveStreamSubscription.fromJson(e as Map<String, Object?>))
          .toList(),
      _ => null,
    },
  );
}
