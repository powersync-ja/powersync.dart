// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'items.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

String _$itemsNotifierHash() => r'0cda92119ac0ce0a22bdaf05d74d17e6b1dc0f4f';

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

abstract class _$ItemsNotifier
    extends BuildlessAutoDisposeStreamNotifier<List<TodoItem>> {
  late final String list;

  Stream<List<TodoItem>> build(
    String list,
  );
}

/// See also [ItemsNotifier].
@ProviderFor(ItemsNotifier)
const itemsNotifierProvider = ItemsNotifierFamily();

/// See also [ItemsNotifier].
class ItemsNotifierFamily extends Family<AsyncValue<List<TodoItem>>> {
  /// See also [ItemsNotifier].
  const ItemsNotifierFamily();

  /// See also [ItemsNotifier].
  ItemsNotifierProvider call(
    String list,
  ) {
    return ItemsNotifierProvider(
      list,
    );
  }

  @override
  ItemsNotifierProvider getProviderOverride(
    covariant ItemsNotifierProvider provider,
  ) {
    return call(
      provider.list,
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
  String? get name => r'itemsNotifierProvider';
}

/// See also [ItemsNotifier].
class ItemsNotifierProvider extends AutoDisposeStreamNotifierProviderImpl<
    ItemsNotifier, List<TodoItem>> {
  /// See also [ItemsNotifier].
  ItemsNotifierProvider(
    String list,
  ) : this._internal(
          () => ItemsNotifier()..list = list,
          from: itemsNotifierProvider,
          name: r'itemsNotifierProvider',
          debugGetCreateSourceHash:
              const bool.fromEnvironment('dart.vm.product')
                  ? null
                  : _$itemsNotifierHash,
          dependencies: ItemsNotifierFamily._dependencies,
          allTransitiveDependencies:
              ItemsNotifierFamily._allTransitiveDependencies,
          list: list,
        );

  ItemsNotifierProvider._internal(
    super._createNotifier, {
    required super.name,
    required super.dependencies,
    required super.allTransitiveDependencies,
    required super.debugGetCreateSourceHash,
    required super.from,
    required this.list,
  }) : super.internal();

  final String list;

  @override
  Stream<List<TodoItem>> runNotifierBuild(
    covariant ItemsNotifier notifier,
  ) {
    return notifier.build(
      list,
    );
  }

  @override
  Override overrideWith(ItemsNotifier Function() create) {
    return ProviderOverride(
      origin: this,
      override: ItemsNotifierProvider._internal(
        () => create()..list = list,
        from: from,
        name: null,
        dependencies: null,
        allTransitiveDependencies: null,
        debugGetCreateSourceHash: null,
        list: list,
      ),
    );
  }

  @override
  AutoDisposeStreamNotifierProviderElement<ItemsNotifier, List<TodoItem>>
      createElement() {
    return _ItemsNotifierProviderElement(this);
  }

  @override
  bool operator ==(Object other) {
    return other is ItemsNotifierProvider && other.list == list;
  }

  @override
  int get hashCode {
    var hash = _SystemHash.combine(0, runtimeType.hashCode);
    hash = _SystemHash.combine(hash, list.hashCode);

    return _SystemHash.finish(hash);
  }
}

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
mixin ItemsNotifierRef on AutoDisposeStreamNotifierProviderRef<List<TodoItem>> {
  /// The parameter `list` of this provider.
  String get list;
}

class _ItemsNotifierProviderElement
    extends AutoDisposeStreamNotifierProviderElement<ItemsNotifier,
        List<TodoItem>> with ItemsNotifierRef {
  _ItemsNotifierProviderElement(super.provider);

  @override
  String get list => (origin as ItemsNotifierProvider).list;
}
// ignore_for_file: type=lint
// ignore_for_file: subtype_of_sealed_class, invalid_use_of_internal_member, invalid_use_of_visible_for_testing_member, deprecated_member_use_from_same_package
