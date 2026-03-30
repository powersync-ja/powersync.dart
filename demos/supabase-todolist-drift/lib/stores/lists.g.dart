// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'lists.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(ListsNotifier)
final listsProvider = ListsNotifierProvider._();

final class ListsNotifierProvider
    extends $StreamNotifierProvider<ListsNotifier, List<ListItemWithStats>> {
  ListsNotifierProvider._()
      : super(
          from: null,
          argument: null,
          retry: null,
          name: r'listsProvider',
          isAutoDispose: true,
          dependencies: null,
          $allTransitiveDependencies: null,
        );

  @override
  String debugGetCreateSourceHash() => _$listsNotifierHash();

  @$internal
  @override
  ListsNotifier create() => ListsNotifier();
}

String _$listsNotifierHash() => r'df074345e9c53161dd648e32853bf0565d57e0a8';

abstract class _$ListsNotifier
    extends $StreamNotifier<List<ListItemWithStats>> {
  Stream<List<ListItemWithStats>> build();
  @$mustCallSuper
  @override
  void runBuild() {
    final ref = this.ref
        as $Ref<AsyncValue<List<ListItemWithStats>>, List<ListItemWithStats>>;
    final element = ref.element as $ClassProviderElement<
        AnyNotifier<AsyncValue<List<ListItemWithStats>>,
            List<ListItemWithStats>>,
        AsyncValue<List<ListItemWithStats>>,
        Object?,
        Object?>;
    element.handleCreate(ref, build);
  }
}
