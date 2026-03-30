// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'photo_widget.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(_getPhotoState)
final _getPhotoStateProvider = _GetPhotoStateFamily._();

final class _GetPhotoStateProvider extends $FunctionalProvider<
        AsyncValue<_ResolvedPhotoState>,
        _ResolvedPhotoState,
        FutureOr<_ResolvedPhotoState>>
    with
        $FutureModifier<_ResolvedPhotoState>,
        $FutureProvider<_ResolvedPhotoState> {
  _GetPhotoStateProvider._(
      {required _GetPhotoStateFamily super.from,
      required String? super.argument})
      : super(
          retry: null,
          name: r'_getPhotoStateProvider',
          isAutoDispose: true,
          dependencies: null,
          $allTransitiveDependencies: null,
        );

  @override
  String debugGetCreateSourceHash() => _$_getPhotoStateHash();

  @override
  String toString() {
    return r'_getPhotoStateProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  $FutureProviderElement<_ResolvedPhotoState> $createElement(
          $ProviderPointer pointer) =>
      $FutureProviderElement(pointer);

  @override
  FutureOr<_ResolvedPhotoState> create(Ref ref) {
    final argument = this.argument as String?;
    return _getPhotoState(
      ref,
      argument,
    );
  }

  @override
  bool operator ==(Object other) {
    return other is _GetPhotoStateProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$_getPhotoStateHash() => r'9dd805dcfabe9288a1e8c125bae75c34d29c494b';

final class _GetPhotoStateFamily extends $Family
    with $FunctionalFamilyOverride<FutureOr<_ResolvedPhotoState>, String?> {
  _GetPhotoStateFamily._()
      : super(
          retry: null,
          name: r'_getPhotoStateProvider',
          dependencies: null,
          $allTransitiveDependencies: null,
          isAutoDispose: true,
        );

  _GetPhotoStateProvider call(
    String? photoId,
  ) =>
      _GetPhotoStateProvider._(argument: photoId, from: this);

  @override
  String toString() => r'_getPhotoStateProvider';
}
