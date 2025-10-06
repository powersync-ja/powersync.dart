/// A platform-specific import supporting attachments on the web.
///
/// This library exports the [OpfsLocalStorage] class, implementing the
/// [LocalStorage] interface by storing files under a root directory.
///
/// {@category attachments}
library;

import '../src/attachments/storage/web_opfs_storage.dart';
import '../src/attachments/storage/local_storage.dart';

export '../src/attachments/storage/web_opfs_storage.dart';
