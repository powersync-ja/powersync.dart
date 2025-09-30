import 'package:powersync_core/attachments/attachments.dart';

Future<LocalStorage> localAttachmentStorage() async {
  // This file is imported on the web, where we don't currently have a
  // persistent local storage implementation.
  return LocalStorage.inMemory();
}
