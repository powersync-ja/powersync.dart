// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'search.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

String _$searchHash() => r'22f755afc645f10c862d9aece9f392958c10d086';

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

/// See also [_search].
@ProviderFor(_search)
const _searchProvider = _SearchFamily();

/// See also [_search].
class _SearchFamily extends Family<AsyncValue<List>> {
  /// See also [_search].
  const _SearchFamily();

  /// See also [_search].
  _SearchProvider call(
    String query,
  ) {
    return _SearchProvider(
      query,
    );
  }

  @override
  _SearchProvider getProviderOverride(
    covariant _SearchProvider provider,
  ) {
    return call(
      provider.query,
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
  String? get name => r'_searchProvider';
}

/// See also [_search].
class _SearchProvider extends AutoDisposeFutureProvider<List> {
  /// See also [_search].
  _SearchProvider(
    String query,
  ) : this._internal(
          (ref) => _search(
            ref as _SearchRef,
            query,
          ),
          from: _searchProvider,
          name: r'_searchProvider',
          debugGetCreateSourceHash:
              const bool.fromEnvironment('dart.vm.product')
                  ? null
                  : _$searchHash,
          dependencies: _SearchFamily._dependencies,
          allTransitiveDependencies: _SearchFamily._allTransitiveDependencies,
          query: query,
        );

  _SearchProvider._internal(
    super._createNotifier, {
    required super.name,
    required super.dependencies,
    required super.allTransitiveDependencies,
    required super.debugGetCreateSourceHash,
    required super.from,
    required this.query,
  }) : super.internal();

  final String query;

  @override
  Override overrideWith(
    FutureOr<List> Function(_SearchRef provider) create,
  ) {
    return ProviderOverride(
      origin: this,
      override: _SearchProvider._internal(
        (ref) => create(ref as _SearchRef),
        from: from,
        name: null,
        dependencies: null,
        allTransitiveDependencies: null,
        debugGetCreateSourceHash: null,
        query: query,
      ),
    );
  }

  @override
  AutoDisposeFutureProviderElement<List> createElement() {
    return _SearchProviderElement(this);
  }

  @override
  bool operator ==(Object other) {
    return other is _SearchProvider && other.query == query;
  }

  @override
  int get hashCode {
    var hash = _SystemHash.combine(0, runtimeType.hashCode);
    hash = _SystemHash.combine(hash, query.hashCode);

    return _SystemHash.finish(hash);
  }
}

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
mixin _SearchRef on AutoDisposeFutureProviderRef<List> {
  /// The parameter `query` of this provider.
  String get query;
}

class _SearchProviderElement extends AutoDisposeFutureProviderElement<List>
    with _SearchRef {
  _SearchProviderElement(super.provider);

  @override
  String get query => (origin as _SearchProvider).query;
}
// ignore_for_file: type=lint
// ignore_for_file: subtype_of_sealed_class, invalid_use_of_internal_member, invalid_use_of_visible_for_testing_member, deprecated_member_use_from_same_package
