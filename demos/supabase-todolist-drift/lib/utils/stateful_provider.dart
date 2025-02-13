import 'package:flutter_riverpod/flutter_riverpod.dart';

final class _StatefulNotifier<T> extends Notifier<T> {
  T? _currentValue;
  final T Function(Ref, void Function(T)) _initial;

  _StatefulNotifier(this._initial);

  @override
  T build() => _currentValue ??= _initial(ref, (updated) {
        _currentValue = state = updated;
      });
}

NotifierProvider<Notifier<T>, T> statefulProvider<T>(
  T Function(Ref ref, void Function(T) change) initialValue,
) {
  return NotifierProvider(() => _StatefulNotifier<T>(initialValue));
}
