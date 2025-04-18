// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'fts_helpers.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

String _$searchHash() => r'44beab2ea36342be88731c46c2988e76058e7fe2';

/// Copied from Dart SDK
class _SystemHash {
  _SystemHash._();

  static int combine(int hash, int value) {
    // ignore: parameter_assignments
    hash = 0x1fffffff & (hash + value);
    // ignore: parameter_assignments
    hash = 0x1fffffff & (hash + ((0x0007ffff & hash) << 10));
    return hash ^ (hash >> 6);
  }

  static int finish(int hash) {
    // ignore: parameter_assignments
    hash = 0x1fffffff & (hash + ((0x03ffffff & hash) << 3));
    // ignore: parameter_assignments
    hash = hash ^ (hash >> 11);
    return 0x1fffffff & (hash + ((0x00003fff & hash) << 15));
  }
}

/// Search the FTS table for the given searchTerm
///
/// Copied from [search].
@ProviderFor(search)
const searchProvider = SearchFamily();

/// Search the FTS table for the given searchTerm
///
/// Copied from [search].
class SearchFamily extends Family<AsyncValue<List>> {
  /// Search the FTS table for the given searchTerm
  ///
  /// Copied from [search].
  const SearchFamily();

  /// Search the FTS table for the given searchTerm
  ///
  /// Copied from [search].
  SearchProvider call(
    String searchTerm,
    String tableName,
  ) {
    return SearchProvider(
      searchTerm,
      tableName,
    );
  }

  @override
  SearchProvider getProviderOverride(
    covariant SearchProvider provider,
  ) {
    return call(
      provider.searchTerm,
      provider.tableName,
    );
  }

  static const Iterable<ProviderOrFamily>? _dependencies = null;

  @override
  Iterable<ProviderOrFamily>? get dependencies => _dependencies;

  static const Iterable<ProviderOrFamily>? _allTransitiveDependencies = null;

  @override
  Iterable<ProviderOrFamily>? get allTransitiveDependencies =>
      _allTransitiveDependencies;

  @override
  String? get name => r'searchProvider';
}

/// Search the FTS table for the given searchTerm
///
/// Copied from [search].
class SearchProvider extends AutoDisposeFutureProvider<List> {
  /// Search the FTS table for the given searchTerm
  ///
  /// Copied from [search].
  SearchProvider(
    String searchTerm,
    String tableName,
  ) : this._internal(
          (ref) => search(
            ref as SearchRef,
            searchTerm,
            tableName,
          ),
          from: searchProvider,
          name: r'searchProvider',
          debugGetCreateSourceHash:
              const bool.fromEnvironment('dart.vm.product')
                  ? null
                  : _$searchHash,
          dependencies: SearchFamily._dependencies,
          allTransitiveDependencies: SearchFamily._allTransitiveDependencies,
          searchTerm: searchTerm,
          tableName: tableName,
        );

  SearchProvider._internal(
    super._createNotifier, {
    required super.name,
    required super.dependencies,
    required super.allTransitiveDependencies,
    required super.debugGetCreateSourceHash,
    required super.from,
    required this.searchTerm,
    required this.tableName,
  }) : super.internal();

  final String searchTerm;
  final String tableName;

  @override
  Override overrideWith(
    FutureOr<List> Function(SearchRef provider) create,
  ) {
    return ProviderOverride(
      origin: this,
      override: SearchProvider._internal(
        (ref) => create(ref as SearchRef),
        from: from,
        name: null,
        dependencies: null,
        allTransitiveDependencies: null,
        debugGetCreateSourceHash: null,
        searchTerm: searchTerm,
        tableName: tableName,
      ),
    );
  }

  @override
  AutoDisposeFutureProviderElement<List> createElement() {
    return _SearchProviderElement(this);
  }

  @override
  bool operator ==(Object other) {
    return other is SearchProvider &&
        other.searchTerm == searchTerm &&
        other.tableName == tableName;
  }

  @override
  int get hashCode {
    var hash = _SystemHash.combine(0, runtimeType.hashCode);
    hash = _SystemHash.combine(hash, searchTerm.hashCode);
    hash = _SystemHash.combine(hash, tableName.hashCode);

    return _SystemHash.finish(hash);
  }
}

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
mixin SearchRef on AutoDisposeFutureProviderRef<List> {
  /// The parameter `searchTerm` of this provider.
  String get searchTerm;

  /// The parameter `tableName` of this provider.
  String get tableName;
}

class _SearchProviderElement extends AutoDisposeFutureProviderElement<List>
    with SearchRef {
  _SearchProviderElement(super.provider);

  @override
  String get searchTerm => (origin as SearchProvider).searchTerm;
  @override
  String get tableName => (origin as SearchProvider).tableName;
}
// ignore_for_file: type=lint
// ignore_for_file: subtype_of_sealed_class, invalid_use_of_internal_member, invalid_use_of_visible_for_testing_member, deprecated_member_use_from_same_package
