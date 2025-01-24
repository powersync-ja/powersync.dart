/// Internal options used to customize how PowerSync opens databases on the web.
library;

export 'src/web/worker_utils.dart' show PowerSyncAdditionalOpenOptions;
export 'package:sqlite_async/sqlite3_web.dart';
export 'package:sqlite_async/web.dart';

import 'src/open_factory/web/web_open_factory.dart';

typedef PowerSyncWebOpenFactory = PowerSyncOpenFactory;
