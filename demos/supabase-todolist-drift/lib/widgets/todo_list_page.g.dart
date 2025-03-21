// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'todo_list_page.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

String _$todosInHash() => r'7f821d25c1e7d6d9fdd9a6e4929572bcfb109401';

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

/// See also [_todosIn].
@ProviderFor(_todosIn)
const _todosInProvider = _TodosInFamily();

/// See also [_todosIn].
class _TodosInFamily extends Family<AsyncValue<List<TodoItem>>> {
  /// See also [_todosIn].
  const _TodosInFamily();

  /// See also [_todosIn].
  _TodosInProvider call(
    String listId,
  ) {
    return _TodosInProvider(
      listId,
    );
  }

  @override
  _TodosInProvider getProviderOverride(
    covariant _TodosInProvider provider,
  ) {
    return call(
      provider.listId,
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
  String? get name => r'_todosInProvider';
}

/// See also [_todosIn].
class _TodosInProvider extends AutoDisposeStreamProvider<List<TodoItem>> {
  /// See also [_todosIn].
  _TodosInProvider(
    String listId,
  ) : this._internal(
          (ref) => _todosIn(
            ref as _TodosInRef,
            listId,
          ),
          from: _todosInProvider,
          name: r'_todosInProvider',
          debugGetCreateSourceHash:
              const bool.fromEnvironment('dart.vm.product')
                  ? null
                  : _$todosInHash,
          dependencies: _TodosInFamily._dependencies,
          allTransitiveDependencies: _TodosInFamily._allTransitiveDependencies,
          listId: listId,
        );

  _TodosInProvider._internal(
    super._createNotifier, {
    required super.name,
    required super.dependencies,
    required super.allTransitiveDependencies,
    required super.debugGetCreateSourceHash,
    required super.from,
    required this.listId,
  }) : super.internal();

  final String listId;

  @override
  Override overrideWith(
    Stream<List<TodoItem>> Function(_TodosInRef provider) create,
  ) {
    return ProviderOverride(
      origin: this,
      override: _TodosInProvider._internal(
        (ref) => create(ref as _TodosInRef),
        from: from,
        name: null,
        dependencies: null,
        allTransitiveDependencies: null,
        debugGetCreateSourceHash: null,
        listId: listId,
      ),
    );
  }

  @override
  AutoDisposeStreamProviderElement<List<TodoItem>> createElement() {
    return _TodosInProviderElement(this);
  }

  @override
  bool operator ==(Object other) {
    return other is _TodosInProvider && other.listId == listId;
  }

  @override
  int get hashCode {
    var hash = _SystemHash.combine(0, runtimeType.hashCode);
    hash = _SystemHash.combine(hash, listId.hashCode);

    return _SystemHash.finish(hash);
  }
}

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
mixin _TodosInRef on AutoDisposeStreamProviderRef<List<TodoItem>> {
  /// The parameter `listId` of this provider.
  String get listId;
}

class _TodosInProviderElement
    extends AutoDisposeStreamProviderElement<List<TodoItem>> with _TodosInRef {
  _TodosInProviderElement(super.provider);

  @override
  String get listId => (origin as _TodosInProvider).listId;
}
// ignore_for_file: type=lint
// ignore_for_file: subtype_of_sealed_class, invalid_use_of_internal_member, invalid_use_of_visible_for_testing_member, deprecated_member_use_from_same_package
