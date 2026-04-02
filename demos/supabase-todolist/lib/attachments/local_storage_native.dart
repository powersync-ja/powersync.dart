import 'package:path_provider/path_provider.dart';
import 'package:powersync/attachments/attachments.dart';
import 'package:powersync/attachments/io.dart';

Future<LocalStorage> localAttachmentStorage() async {
  final appDocDir = await getApplicationDocumentsDirectory();
  return IOLocalStorage(appDocDir);
}
