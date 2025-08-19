/// A platform-specific import supporting attachments on native platforms.
///
/// This library exports the [IOLocalStorage] class, implementing the
/// [LocalStorageAdapter] interface by storing files under a root directory.
///
/// {@category attachments}
library;

import '../src/attachments/io_local_storage.dart';
import '../src/attachments/local_storage.dart';

export '../src/attachments/io_local_storage.dart';
