import 'package:devtools_extensions/devtools_extensions.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:vm_service/vm_service.dart';

extension<T> on ValueListenable<T> {
  Stream<T> get asStream {
    return Stream.multi((listener) {
      listener.add(value);

      void valueListener() {
        listener.add(value);
      }

      void addListener() {
        this.addListener(valueListener);
      }

      void removeListener() {
        this.removeListener(valueListener);
      }

      addListener();
      listener
        ..onPause = removeListener
        ..onResume = addListener
        ..onCancel = removeListener;
    });
  }
}

final serviceProvider = StreamProvider<VmService>((ref) {
  final state = serviceManager.connectedState.asStream;
  return state.where((c) => c.connected).map((_) => serviceManager.service!);
});

final isolateProvider = ChangeNotifierProvider<ValueNotifier<IsolateRef?>>((
  ref,
) {
  final selectedIsolateListenable =
      serviceManager.isolateManager.selectedIsolate;

  // Since ChangeNotifierProvider calls `dispose` on the returned ChangeNotifier
  // when the provider is destroyed, we can't simply return `selectedIsolateListenable`.
  // So we're making a copy of it instead.
  final notifier = ValueNotifier<IsolateRef?>(selectedIsolateListenable.value);

  void listener() => notifier.value = selectedIsolateListenable.value;
  selectedIsolateListenable.addListener(listener);
  ref.onDispose(() => selectedIsolateListenable.removeListener(listener));

  return notifier;
});
