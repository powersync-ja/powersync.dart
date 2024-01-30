import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';
import 'package:uuid/data.dart';
import 'package:uuid/rng.dart';

final uuid = kIsWeb ? Uuid() : Uuid(goptions: GlobalOptions(CryptoRNG()));
