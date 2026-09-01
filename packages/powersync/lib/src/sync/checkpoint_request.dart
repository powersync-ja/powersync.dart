import 'package:meta/meta.dart';

/// An exception related to requested checkpoints for PowerSync.
final class CheckpointRequestException implements Exception {
  final String _message;

  const CheckpointRequestException._(this._message);

  @override
  String toString() => _message;
}

@internal
const instanceNotSupported = CheckpointRequestException._(
  'The PowerSync service does not support checkpoint requests. Update to PowerSync service version 1.24.0 or later to use this API.',
);

@internal
const disconnected = CheckpointRequestException._(
  'Cannot request checkpoints, sync client is disconnected',
);

@internal
const disabled = CheckpointRequestException._(
  'Connected with legacy checkpoint mode, cannot request checkpoints',
);
