// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'items.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(ItemsNotifier)
final itemsProvider = ItemsNotifierFamily._();

final class ItemsNotifierProvider
    extends $StreamNotifierProvider<ItemsNotifier, List<TodoItem>> {
  ItemsNotifierProvider._(
      {required ItemsNotifierFamily super.from, required String super.argument})
      : super(
          retry: null,
          name: r'itemsProvider',
          isAutoDispose: true,
          dependencies: null,
          $allTransitiveDependencies: null,
        );

  @override
  String debugGetCreateSourceHash() => _$itemsNotifierHash();

  @override
  String toString() {
    return r'itemsProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  ItemsNotifier create() => ItemsNotifier();

  @override
  bool operator ==(Object other) {
    return other is ItemsNotifierProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$itemsNotifierHash() => r'23fa85ab084d323c3ad8d5ff3efcd900b73ce90a';

final class ItemsNotifierFamily extends $Family
    with
        $ClassFamilyOverride<ItemsNotifier, AsyncValue<List<TodoItem>>,
            List<TodoItem>, Stream<List<TodoItem>>, String> {
  ItemsNotifierFamily._()
      : super(
          retry: null,
          name: r'itemsProvider',
          dependencies: null,
          $allTransitiveDependencies: null,
          isAutoDispose: true,
        );

  ItemsNotifierProvider call(
    String list,
  ) =>
      ItemsNotifierProvider._(argument: list, from: this);

  @override
  String toString() => r'itemsProvider';
}

abstract class _$ItemsNotifier extends $StreamNotifier<List<TodoItem>> {
  late final _$args = ref.$arg as String;
  String get list => _$args;

  Stream<List<TodoItem>> build(
    String list,
  );
  @$mustCallSuper
  @override
  void runBuild() {
    final ref = this.ref as $Ref<AsyncValue<List<TodoItem>>, List<TodoItem>>;
    final element = ref.element as $ClassProviderElement<
        AnyNotifier<AsyncValue<List<TodoItem>>, List<TodoItem>>,
        AsyncValue<List<TodoItem>>,
        Object?,
        Object?>;
    element.handleCreate(
        ref,
        () => build(
              _$args,
            ));
  }
}
