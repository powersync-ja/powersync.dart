import 'package:logging/logging.dart';
import 'package:riverpod/riverpod.dart';

final class LoggingProviderObserver extends ProviderObserver {
  static final _log = Logger('provider');

  const LoggingProviderObserver();

  @override
  void didUpdateProvider(
    ProviderObserverContext context,
    Object? previousValue,
    Object? newValue,
  ) {
    if (newValue case AsyncError(:final error, :final stackTrace)) {
      _log.warning(
          '${context.provider} emitted async error', error, stackTrace);
    }
  }

  @override
  void providerDidFail(
    ProviderObserverContext context,
    Object error,
    StackTrace stackTrace,
  ) {
    _log.warning('${context.provider} threw exception', error, stackTrace);
  }
}
