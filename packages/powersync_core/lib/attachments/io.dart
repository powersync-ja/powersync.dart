/// A platform-specific import supporting attachments on native platforms.
///
/// This library exports the [IOLocalStorage] class, implementing the
/// [LocalStorage] interface by storing files under a root directory.
///
/// {@category attachments}
library;

import '../src/attachments/storage/io_local_storage.dart';
import '../src/attachments/storage/local_storage.dart';

export '../src/attachments/storage/io_local_storage.dart';
