// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'sql_console.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

String _$watchHash() => r'd184cf5e1c494c80f42ad490e989911be7fce98a';

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

/// See also [_watch].
@ProviderFor(_watch)
const _watchProvider = _WatchFamily();

/// See also [_watch].
class _WatchFamily extends Family<AsyncValue<sqlite.ResultSet>> {
  /// See also [_watch].
  const _WatchFamily();

  /// See also [_watch].
  _WatchProvider call(
    String sql,
  ) {
    return _WatchProvider(
      sql,
    );
  }

  @override
  _WatchProvider getProviderOverride(
    covariant _WatchProvider provider,
  ) {
    return call(
      provider.sql,
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
  String? get name => r'_watchProvider';
}

/// See also [_watch].
class _WatchProvider extends AutoDisposeStreamProvider<sqlite.ResultSet> {
  /// See also [_watch].
  _WatchProvider(
    String sql,
  ) : this._internal(
          (ref) => _watch(
            ref as _WatchRef,
            sql,
          ),
          from: _watchProvider,
          name: r'_watchProvider',
          debugGetCreateSourceHash:
              const bool.fromEnvironment('dart.vm.product')
                  ? null
                  : _$watchHash,
          dependencies: _WatchFamily._dependencies,
          allTransitiveDependencies: _WatchFamily._allTransitiveDependencies,
          sql: sql,
        );

  _WatchProvider._internal(
    super._createNotifier, {
    required super.name,
    required super.dependencies,
    required super.allTransitiveDependencies,
    required super.debugGetCreateSourceHash,
    required super.from,
    required this.sql,
  }) : super.internal();

  final String sql;

  @override
  Override overrideWith(
    Stream<sqlite.ResultSet> Function(_WatchRef provider) create,
  ) {
    return ProviderOverride(
      origin: this,
      override: _WatchProvider._internal(
        (ref) => create(ref as _WatchRef),
        from: from,
        name: null,
        dependencies: null,
        allTransitiveDependencies: null,
        debugGetCreateSourceHash: null,
        sql: sql,
      ),
    );
  }

  @override
  AutoDisposeStreamProviderElement<sqlite.ResultSet> createElement() {
    return _WatchProviderElement(this);
  }

  @override
  bool operator ==(Object other) {
    return other is _WatchProvider && other.sql == sql;
  }

  @override
  int get hashCode {
    var hash = _SystemHash.combine(0, runtimeType.hashCode);
    hash = _SystemHash.combine(hash, sql.hashCode);

    return _SystemHash.finish(hash);
  }
}

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
mixin _WatchRef on AutoDisposeStreamProviderRef<sqlite.ResultSet> {
  /// The parameter `sql` of this provider.
  String get sql;
}

class _WatchProviderElement
    extends AutoDisposeStreamProviderElement<sqlite.ResultSet> with _WatchRef {
  _WatchProviderElement(super.provider);

  @override
  String get sql => (origin as _WatchProvider).sql;
}
// ignore_for_file: type=lint
// ignore_for_file: subtype_of_sealed_class, invalid_use_of_internal_member, invalid_use_of_visible_for_testing_member, deprecated_member_use_from_same_package
