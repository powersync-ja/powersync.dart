import 'bucket_storage.dart';

class Checkpoint {
  final String lastOpId;
  final String? writeCheckpoint;
  final List<BucketChecksum> checksums;

  const Checkpoint(
      {required this.lastOpId, required this.checksums, this.writeCheckpoint});

  Checkpoint.fromJson(Map<String, dynamic> json)
      : lastOpId = json['last_op_id'],
        writeCheckpoint = json['write_checkpoint'],
        checksums = (json['buckets'] as List)
            .map((b) => BucketChecksum.fromJson(b))
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
      : bucket = json['bucket'],
        checksum = json['checksum'],
        count = json['count'],
        lastOpId = json['last_op_id'];
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
      : lastOpId = json['last_op_id'],
        writeCheckpoint = json['write_checkpoint'],
        updatedBuckets = (json['updated_buckets'] as List)
            .map((e) => BucketChecksum.fromJson(e))
            .toList(),
        removedBuckets = List<String>.from(json['removed_buckets']);
}

class StreamingSyncCheckpointComplete {
  String lastOpId;

  StreamingSyncCheckpointComplete(this.lastOpId);

  StreamingSyncCheckpointComplete.fromJson(Map<String, dynamic> json)
      : lastOpId = json['last_op_id'];
}

class StreamingSyncKeepalive {
  int tokenExpiresIn;

  StreamingSyncKeepalive(this.tokenExpiresIn);

  StreamingSyncKeepalive.fromJson(Map<String, dynamic> json)
      : tokenExpiresIn = json['token_expires_in'];
}

Object? parseStreamingSyncLine(Map<String, dynamic> line) {
  if (line.containsKey('checkpoint')) {
    return Checkpoint.fromJson(line['checkpoint']);
  } else if (line.containsKey('checkpoint_diff')) {
    return StreamingSyncCheckpointDiff.fromJson(line['checkpoint_diff']);
  } else if (line.containsKey('checkpoint_complete')) {
    return StreamingSyncCheckpointComplete.fromJson(
        line['checkpoint_complete']);
  } else if (line.containsKey('data')) {
    return SyncBucketData.fromJson(line['data']);
  } else if (line.containsKey('token_expires_in')) {
    return StreamingSyncKeepalive.fromJson(line);
  } else {
    return null;
  }
}

class StreamingSyncRequest {
  List<BucketRequest> buckets;
  bool includeChecksum = true;

  StreamingSyncRequest(this.buckets);

  Map<String, dynamic> toJson() => {
        'buckets': buckets,
        'include_checksum': includeChecksum,
        // We want the JSON row data as a string
        'raw_data': true
      };
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
