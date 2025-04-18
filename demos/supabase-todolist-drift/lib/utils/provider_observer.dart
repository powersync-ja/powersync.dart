import 'package:logging/logging.dart';
import 'package:riverpod/riverpod.dart';

final class LoggingProviderObserver extends ProviderObserver {
  static final _log = Logger('provider');

  const LoggingProviderObserver();

  @override
  void didUpdateProvider(ProviderBase<Object?> provider, Object? previousValue,
      Object? newValue, ProviderContainer container) {
    if (newValue case AsyncError(:final error, :final stackTrace)) {
      _log.warning('$provider emitted async error', error, stackTrace);
    }
  }

  @override
  void providerDidFail(ProviderBase<Object?> provider, Object error,
      StackTrace stackTrace, ProviderContainer container) {
    _log.warning('$provider threw exception', error, stackTrace);
  }
}
