// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'queue.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(attachmentQueue)
final attachmentQueueProvider = AttachmentQueueProvider._();

final class AttachmentQueueProvider extends $FunctionalProvider<
        AsyncValue<PhotoAttachmentQueue>,
        PhotoAttachmentQueue,
        FutureOr<PhotoAttachmentQueue>>
    with
        $FutureModifier<PhotoAttachmentQueue>,
        $FutureProvider<PhotoAttachmentQueue> {
  AttachmentQueueProvider._()
      : super(
          from: null,
          argument: null,
          retry: null,
          name: r'attachmentQueueProvider',
          isAutoDispose: false,
          dependencies: null,
          $allTransitiveDependencies: null,
        );

  @override
  String debugGetCreateSourceHash() => _$attachmentQueueHash();

  @$internal
  @override
  $FutureProviderElement<PhotoAttachmentQueue> $createElement(
          $ProviderPointer pointer) =>
      $FutureProviderElement(pointer);

  @override
  FutureOr<PhotoAttachmentQueue> create(Ref ref) {
    return attachmentQueue(ref);
  }
}

String _$attachmentQueueHash() => r'353be28d71ad41994abf783776a99881e0b51383';
