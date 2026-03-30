// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'sql_console.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(_watch)
final _watchProvider = _WatchFamily._();

final class _WatchProvider extends $FunctionalProvider<
        AsyncValue<sqlite.ResultSet>,
        sqlite.ResultSet,
        Stream<sqlite.ResultSet>>
    with $FutureModifier<sqlite.ResultSet>, $StreamProvider<sqlite.ResultSet> {
  _WatchProvider._(
      {required _WatchFamily super.from, required String super.argument})
      : super(
          retry: null,
          name: r'_watchProvider',
          isAutoDispose: true,
          dependencies: null,
          $allTransitiveDependencies: null,
        );

  @override
  String debugGetCreateSourceHash() => _$_watchHash();

  @override
  String toString() {
    return r'_watchProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  $StreamProviderElement<sqlite.ResultSet> $createElement(
          $ProviderPointer pointer) =>
      $StreamProviderElement(pointer);

  @override
  Stream<sqlite.ResultSet> create(Ref ref) {
    final argument = this.argument as String;
    return _watch(
      ref,
      argument,
    );
  }

  @override
  bool operator ==(Object other) {
    return other is _WatchProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$_watchHash() => r'd184cf5e1c494c80f42ad490e989911be7fce98a';

final class _WatchFamily extends $Family
    with $FunctionalFamilyOverride<Stream<sqlite.ResultSet>, String> {
  _WatchFamily._()
      : super(
          retry: null,
          name: r'_watchProvider',
          dependencies: null,
          $allTransitiveDependencies: null,
          isAutoDispose: true,
        );

  _WatchProvider call(
    String sql,
  ) =>
      _WatchProvider._(argument: sql, from: this);

  @override
  String toString() => r'_watchProvider';
}
