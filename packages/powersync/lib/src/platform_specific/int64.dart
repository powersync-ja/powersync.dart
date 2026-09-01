import 'platform_specific.dart';

/// A signed 64-bit integer.
///
/// We can't use [int] values directly because they're backed by [double]s on
/// the web. At the same time, we want to avoid using [BigInt] on native
/// platforms. We also don't use `package:fixnum` since it doesn't use the Dart
/// native implementation when compiled to WebAssembly.
abstract interface class Int64 {
  static Int64 parse(String s) => parseInt64(s);

  bool operator >=(Int64 other);

  /// Whether the native Dart [int] type is backed by a real 64-bit integer
  /// (that is, we're not compiling to JavaScript).
  static const bool has64BitIntegers = !identical(0, 0.0);
}

final class NativeInt64 implements Int64 {
  final int value;

  NativeInt64(this.value) : assert(Int64.has64BitIntegers);

  static NativeInt64 parse(String s) => NativeInt64(int.parse(s));

  @override
  bool operator >=(Int64 other) => other is NativeInt64 && value >= other.value;

  @override
  String toString() => value.toString();

  @override
  int get hashCode => value.hashCode;

  @override
  bool operator ==(Object other) =>
      other is NativeInt64 && value == other.value;
}
