// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'fts_helpers.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// Search the FTS table for the given searchTerm

@ProviderFor(search)
final searchProvider = SearchFamily._();

/// Search the FTS table for the given searchTerm

final class SearchProvider extends $FunctionalProvider<
        AsyncValue<List<dynamic>>, List<dynamic>, FutureOr<List<dynamic>>>
    with $FutureModifier<List<dynamic>>, $FutureProvider<List<dynamic>> {
  /// Search the FTS table for the given searchTerm
  SearchProvider._(
      {required SearchFamily super.from,
      required (
        String,
        String,
      )
          super.argument})
      : super(
          retry: null,
          name: r'searchProvider',
          isAutoDispose: true,
          dependencies: null,
          $allTransitiveDependencies: null,
        );

  @override
  String debugGetCreateSourceHash() => _$searchHash();

  @override
  String toString() {
    return r'searchProvider'
        ''
        '$argument';
  }

  @$internal
  @override
  $FutureProviderElement<List<dynamic>> $createElement(
          $ProviderPointer pointer) =>
      $FutureProviderElement(pointer);

  @override
  FutureOr<List<dynamic>> create(Ref ref) {
    final argument = this.argument as (
      String,
      String,
    );
    return search(
      ref,
      argument.$1,
      argument.$2,
    );
  }

  @override
  bool operator ==(Object other) {
    return other is SearchProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$searchHash() => r'44beab2ea36342be88731c46c2988e76058e7fe2';

/// Search the FTS table for the given searchTerm

final class SearchFamily extends $Family
    with
        $FunctionalFamilyOverride<
            FutureOr<List<dynamic>>,
            (
              String,
              String,
            )> {
  SearchFamily._()
      : super(
          retry: null,
          name: r'searchProvider',
          dependencies: null,
          $allTransitiveDependencies: null,
          isAutoDispose: true,
        );

  /// Search the FTS table for the given searchTerm

  SearchProvider call(
    String searchTerm,
    String tableName,
  ) =>
      SearchProvider._(argument: (
        searchTerm,
        tableName,
      ), from: this);

  @override
  String toString() => r'searchProvider';
}
