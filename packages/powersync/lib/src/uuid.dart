import 'package:uuid/uuid.dart';
import 'package:uuid/data.dart';
import 'package:uuid/rng.dart';

final uuid = Uuid(goptions: GlobalOptions(CryptoRNG()));
