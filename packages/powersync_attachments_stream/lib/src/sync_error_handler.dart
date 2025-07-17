import 'attachment_state.dart';

abstract class SyncErrorHandler {
  /// Return true to retry, false to skip/fail
  Future<bool> onError(Object error, StackTrace stack, {Attachment? attachment});
}