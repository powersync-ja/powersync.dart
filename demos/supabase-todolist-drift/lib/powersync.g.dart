// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'powersync.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

String _$isLoggedInHash() => r'4de54b56ee8d5bba766f81dcbcfe033f3c905250';

/// See also [isLoggedIn].
@ProviderFor(isLoggedIn)
final isLoggedInProvider = AutoDisposeProvider<bool>.internal(
  isLoggedIn,
  name: r'isLoggedInProvider',
  debugGetCreateSourceHash:
      const bool.fromEnvironment('dart.vm.product') ? null : _$isLoggedInHash,
  dependencies: null,
  allTransitiveDependencies: null,
);

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
typedef IsLoggedInRef = AutoDisposeProviderRef<bool>;
String _$userIdHash() => r'0489ac84e34b0d0da777bbd4a46a72db1c065963';

/// See also [userId].
@ProviderFor(userId)
final userIdProvider = AutoDisposeProvider<String?>.internal(
  userId,
  name: r'userIdProvider',
  debugGetCreateSourceHash:
      const bool.fromEnvironment('dart.vm.product') ? null : _$userIdHash,
  dependencies: null,
  allTransitiveDependencies: null,
);

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
typedef UserIdRef = AutoDisposeProviderRef<String?>;
String _$didCompleteSyncHash() => r'532f9cd620c43578b58452907e2165eba6745c21';

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

/// See also [didCompleteSync].
@ProviderFor(didCompleteSync)
const didCompleteSyncProvider = DidCompleteSyncFamily();

/// See also [didCompleteSync].
class DidCompleteSyncFamily extends Family<bool> {
  /// See also [didCompleteSync].
  const DidCompleteSyncFamily();

  /// See also [didCompleteSync].
  DidCompleteSyncProvider call([
    BucketPriority? priority,
  ]) {
    return DidCompleteSyncProvider(
      priority,
    );
  }

  @override
  DidCompleteSyncProvider getProviderOverride(
    covariant DidCompleteSyncProvider provider,
  ) {
    return call(
      provider.priority,
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
  String? get name => r'didCompleteSyncProvider';
}

/// See also [didCompleteSync].
class DidCompleteSyncProvider extends AutoDisposeProvider<bool> {
  /// See also [didCompleteSync].
  DidCompleteSyncProvider([
    BucketPriority? priority,
  ]) : this._internal(
          (ref) => didCompleteSync(
            ref as DidCompleteSyncRef,
            priority,
          ),
          from: didCompleteSyncProvider,
          name: r'didCompleteSyncProvider',
          debugGetCreateSourceHash:
              const bool.fromEnvironment('dart.vm.product')
                  ? null
                  : _$didCompleteSyncHash,
          dependencies: DidCompleteSyncFamily._dependencies,
          allTransitiveDependencies:
              DidCompleteSyncFamily._allTransitiveDependencies,
          priority: priority,
        );

  DidCompleteSyncProvider._internal(
    super._createNotifier, {
    required super.name,
    required super.dependencies,
    required super.allTransitiveDependencies,
    required super.debugGetCreateSourceHash,
    required super.from,
    required this.priority,
  }) : super.internal();

  final BucketPriority? priority;

  @override
  Override overrideWith(
    bool Function(DidCompleteSyncRef provider) create,
  ) {
    return ProviderOverride(
      origin: this,
      override: DidCompleteSyncProvider._internal(
        (ref) => create(ref as DidCompleteSyncRef),
        from: from,
        name: null,
        dependencies: null,
        allTransitiveDependencies: null,
        debugGetCreateSourceHash: null,
        priority: priority,
      ),
    );
  }

  @override
  AutoDisposeProviderElement<bool> createElement() {
    return _DidCompleteSyncProviderElement(this);
  }

  @override
  bool operator ==(Object other) {
    return other is DidCompleteSyncProvider && other.priority == priority;
  }

  @override
  int get hashCode {
    var hash = _SystemHash.combine(0, runtimeType.hashCode);
    hash = _SystemHash.combine(hash, priority.hashCode);

    return _SystemHash.finish(hash);
  }
}

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
mixin DidCompleteSyncRef on AutoDisposeProviderRef<bool> {
  /// The parameter `priority` of this provider.
  BucketPriority? get priority;
}

class _DidCompleteSyncProviderElement extends AutoDisposeProviderElement<bool>
    with DidCompleteSyncRef {
  _DidCompleteSyncProviderElement(super.provider);

  @override
  BucketPriority? get priority => (origin as DidCompleteSyncProvider).priority;
}

String _$powerSyncInstanceHash() => r'a32863d59e048c98eacc818387ee902bab8d778c';

/// See also [PowerSyncInstance].
@ProviderFor(PowerSyncInstance)
final powerSyncInstanceProvider =
    AsyncNotifierProvider<PowerSyncInstance, PowerSyncDatabase>.internal(
  PowerSyncInstance.new,
  name: r'powerSyncInstanceProvider',
  debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
      ? null
      : _$powerSyncInstanceHash,
  dependencies: null,
  allTransitiveDependencies: null,
);

typedef _$PowerSyncInstance = AsyncNotifier<PowerSyncDatabase>;
// ignore_for_file: type=lint
// ignore_for_file: subtype_of_sealed_class, invalid_use_of_internal_member, invalid_use_of_visible_for_testing_member, deprecated_member_use_from_same_package
