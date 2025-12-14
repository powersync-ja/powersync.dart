import 'package:powersync_core/attachments/attachments.dart';
import 'package:powersync_core/attachments/web.dart';

Future<LocalStorage> localAttachmentStorage() async {
  return OpfsLocalStorage('powersync_attachments');
}
