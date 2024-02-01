import 'package:uuid/uuid.dart';
import 'package:uuid/data.dart';
import 'package:uuid/rng.dart';

import 'log_internal.dart';

final uuid = kIsWeb ? Uuid() : Uuid(goptions: GlobalOptions(CryptoRNG()));
