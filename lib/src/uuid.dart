import 'dart:math';
import 'dart:typed_data';

import 'package:uuid/uuid.dart';

final _secureRandom = Random.secure();

// Around 2x faster than the implementation from package:uuid/uuid_util.dart
Uint8List cryptoRNG() {
  final b = Uint8List(16);

  for (var i = 0; i < 16; i += 4) {
    var k = _secureRandom.nextInt(1 << 32);
    b[i] = k;
    b[i + 1] = k >> 8;
    b[i + 2] = k >> 16;
    b[i + 3] = k >> 24;
  }

  return b;
}

const uuid = Uuid(options: {'grng': cryptoRNG});
