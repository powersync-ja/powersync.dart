// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'search.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(_search)
final _searchProvider = _SearchFamily._();

final class _SearchProvider extends $FunctionalProvider<
        AsyncValue<List<dynamic>>, List<dynamic>, FutureOr<List<dynamic>>>
    with $FutureModifier<List<dynamic>>, $FutureProvider<List<dynamic>> {
  _SearchProvider._(
      {required _SearchFamily super.from, required String super.argument})
      : super(
          retry: null,
          name: r'_searchProvider',
          isAutoDispose: true,
          dependencies: null,
          $allTransitiveDependencies: null,
        );

  @override
  String debugGetCreateSourceHash() => _$_searchHash();

  @override
  String toString() {
    return r'_searchProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  $FutureProviderElement<List<dynamic>> $createElement(
          $ProviderPointer pointer) =>
      $FutureProviderElement(pointer);

  @override
  FutureOr<List<dynamic>> create(Ref ref) {
    final argument = this.argument as String;
    return _search(
      ref,
      argument,
    );
  }

  @override
  bool operator ==(Object other) {
    return other is _SearchProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$_searchHash() => r'22f755afc645f10c862d9aece9f392958c10d086';

final class _SearchFamily extends $Family
    with $FunctionalFamilyOverride<FutureOr<List<dynamic>>, String> {
  _SearchFamily._()
      : super(
          retry: null,
          name: r'_searchProvider',
          dependencies: null,
          $allTransitiveDependencies: null,
          isAutoDispose: true,
        );

  _SearchProvider call(
    String query,
  ) =>
      _SearchProvider._(argument: query, from: this);

  @override
  String toString() => r'_searchProvider';
}
