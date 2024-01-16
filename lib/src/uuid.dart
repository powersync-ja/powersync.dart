import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';
import 'package:uuid/data.dart';
import 'package:uuid/rng.dart';

final _secureRandom = Random.secure();

/// Around 2x faster than CryptoRNG from package:uuid/rng.dart
class FasterCryptoRNG extends RNG {
  const FasterCryptoRNG();

  @override
  Uint8List generateInternal() {
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
}

const uuid = kIsWeb ? Uuid() : Uuid(goptions: GlobalOptions(FasterCryptoRNG()));
