import 'bucket_storage.dart';

class Checkpoint {
  final String lastOpId;
  final String? writeCheckpoint;
  final List<BucketChecksum> checksums;

  const Checkpoint(
      {required this.lastOpId, required this.checksums, this.writeCheckpoint});

  Checkpoint.fromJson(Map<String, dynamic> json)
      : lastOpId = json['last_op_id'] as String,
        writeCheckpoint = json['write_checkpoint'] as String?,
        checksums = (json['buckets'] as List)
            .map((b) => BucketChecksum.fromJson(b as Map<String, dynamic>))
            .toList();

  Map<String, dynamic> toJson() {
    return {
      'last_op_id': lastOpId,
      'write_checkpoint': writeCheckpoint,
      'buckets': checksums
          .map((c) => {'bucket': c.bucket, 'checksum': c.checksum})
          .toList(growable: false)
    };
  }
}

class BucketChecksum {
  final String bucket;
  final int checksum;

  /// Count is informational only
  final int? count;
  final String? lastOpId;

  const BucketChecksum(
      {required this.bucket,
      required this.checksum,
      this.count,
      this.lastOpId});

  BucketChecksum.fromJson(Map<String, dynamic> json)
      : bucket = json['bucket'] as String,
        checksum = json['checksum'] as int,
        count = json['count'] as int?,
        lastOpId = json['last_op_id'] as String?;
}

class StreamingSyncCheckpoint {
  Checkpoint checkpoint;

  StreamingSyncCheckpoint(this.checkpoint);

  StreamingSyncCheckpoint.fromJson(Map<String, dynamic> json)
      : checkpoint = Checkpoint.fromJson(json);
}

class StreamingSyncCheckpointDiff {
  String lastOpId;
  List<BucketChecksum> updatedBuckets;
  List<String> removedBuckets;
  String? writeCheckpoint;

  StreamingSyncCheckpointDiff(
      this.lastOpId, this.updatedBuckets, this.removedBuckets);

  StreamingSyncCheckpointDiff.fromJson(Map<String, dynamic> json)
      : lastOpId = json['last_op_id'] as String,
        writeCheckpoint = json['write_checkpoint'] as String?,
        updatedBuckets = (json['updated_buckets'] as List)
            .map((e) => BucketChecksum.fromJson(e as Map<String, Object?>))
            .toList(),
        removedBuckets = (json['removed_buckets'] as List).cast();
}

class StreamingSyncCheckpointComplete {
  String lastOpId;

  StreamingSyncCheckpointComplete(this.lastOpId);

  StreamingSyncCheckpointComplete.fromJson(Map<String, dynamic> json)
      : lastOpId = json['last_op_id'] as String;
}

class StreamingSyncKeepalive {
  int tokenExpiresIn;

  StreamingSyncKeepalive(this.tokenExpiresIn);

  StreamingSyncKeepalive.fromJson(Map<String, dynamic> json)
      : tokenExpiresIn = json['token_expires_in'] as int;
}

Object? parseStreamingSyncLine(Map<String, dynamic> line) {
  if (line.containsKey('checkpoint')) {
    return Checkpoint.fromJson(line['checkpoint'] as Map<String, dynamic>);
  } else if (line.containsKey('checkpoint_diff')) {
    return StreamingSyncCheckpointDiff.fromJson(
        line['checkpoint_diff'] as Map<String, dynamic>);
  } else if (line.containsKey('checkpoint_complete')) {
    return StreamingSyncCheckpointComplete.fromJson(
        line['checkpoint_complete'] as Map<String, dynamic>);
  } else if (line.containsKey('data')) {
    return SyncBucketData.fromJson(line['data'] as Map<String, dynamic>);
  } else if (line.containsKey('token_expires_in')) {
    return StreamingSyncKeepalive.fromJson(line);
  } else {
    return null;
  }
}

class StreamingSyncRequest {
  List<BucketRequest> buckets;
  bool includeChecksum = true;
  String clientId;
  Map<String, dynamic>? parameters;

  StreamingSyncRequest(this.buckets, this.parameters, this.clientId);

  Map<String, dynamic> toJson() {
    final Map<String, dynamic> json = {
      'buckets': buckets,
      'include_checksum': includeChecksum,
      'raw_data': true,
      'client_id': clientId
    };

    if (parameters != null) {
      json['parameters'] = parameters;
    }

    return json;
  }
}

class BucketRequest {
  String name;
  String after;

  BucketRequest(this.name, this.after);

  Map<String, dynamic> toJson() => {
        'name': name,
        'after': after,
      };
}
