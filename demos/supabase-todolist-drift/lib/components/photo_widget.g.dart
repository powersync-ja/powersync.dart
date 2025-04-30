// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'photo_widget.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

String _$getPhotoStateHash() => r'9dd805dcfabe9288a1e8c125bae75c34d29c494b';

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

/// See also [_getPhotoState].
@ProviderFor(_getPhotoState)
const _getPhotoStateProvider = _GetPhotoStateFamily();

/// See also [_getPhotoState].
class _GetPhotoStateFamily extends Family<AsyncValue<_ResolvedPhotoState>> {
  /// See also [_getPhotoState].
  const _GetPhotoStateFamily();

  /// See also [_getPhotoState].
  _GetPhotoStateProvider call(
    String? photoId,
  ) {
    return _GetPhotoStateProvider(
      photoId,
    );
  }

  @override
  _GetPhotoStateProvider getProviderOverride(
    covariant _GetPhotoStateProvider provider,
  ) {
    return call(
      provider.photoId,
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
  String? get name => r'_getPhotoStateProvider';
}

/// See also [_getPhotoState].
class _GetPhotoStateProvider
    extends AutoDisposeFutureProvider<_ResolvedPhotoState> {
  /// See also [_getPhotoState].
  _GetPhotoStateProvider(
    String? photoId,
  ) : this._internal(
          (ref) => _getPhotoState(
            ref as _GetPhotoStateRef,
            photoId,
          ),
          from: _getPhotoStateProvider,
          name: r'_getPhotoStateProvider',
          debugGetCreateSourceHash:
              const bool.fromEnvironment('dart.vm.product')
                  ? null
                  : _$getPhotoStateHash,
          dependencies: _GetPhotoStateFamily._dependencies,
          allTransitiveDependencies:
              _GetPhotoStateFamily._allTransitiveDependencies,
          photoId: photoId,
        );

  _GetPhotoStateProvider._internal(
    super._createNotifier, {
    required super.name,
    required super.dependencies,
    required super.allTransitiveDependencies,
    required super.debugGetCreateSourceHash,
    required super.from,
    required this.photoId,
  }) : super.internal();

  final String? photoId;

  @override
  Override overrideWith(
    FutureOr<_ResolvedPhotoState> Function(_GetPhotoStateRef provider) create,
  ) {
    return ProviderOverride(
      origin: this,
      override: _GetPhotoStateProvider._internal(
        (ref) => create(ref as _GetPhotoStateRef),
        from: from,
        name: null,
        dependencies: null,
        allTransitiveDependencies: null,
        debugGetCreateSourceHash: null,
        photoId: photoId,
      ),
    );
  }

  @override
  AutoDisposeFutureProviderElement<_ResolvedPhotoState> createElement() {
    return _GetPhotoStateProviderElement(this);
  }

  @override
  bool operator ==(Object other) {
    return other is _GetPhotoStateProvider && other.photoId == photoId;
  }

  @override
  int get hashCode {
    var hash = _SystemHash.combine(0, runtimeType.hashCode);
    hash = _SystemHash.combine(hash, photoId.hashCode);

    return _SystemHash.finish(hash);
  }
}

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
mixin _GetPhotoStateRef on AutoDisposeFutureProviderRef<_ResolvedPhotoState> {
  /// The parameter `photoId` of this provider.
  String? get photoId;
}

class _GetPhotoStateProviderElement
    extends AutoDisposeFutureProviderElement<_ResolvedPhotoState>
    with _GetPhotoStateRef {
  _GetPhotoStateProviderElement(super.provider);

  @override
  String? get photoId => (origin as _GetPhotoStateProvider).photoId;
}
// ignore_for_file: type=lint
// ignore_for_file: subtype_of_sealed_class, invalid_use_of_internal_member, invalid_use_of_visible_for_testing_member, deprecated_member_use_from_same_package
