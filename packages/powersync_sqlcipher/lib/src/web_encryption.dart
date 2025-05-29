import 'package:powersync_core/web.dart';

import 'shared.dart';

class _WebEncryptionFactory extends PowerSyncWebOpenFactory
    with BaseSQLCipherFactoryMixin {
  @override
  final String key;

  _WebEncryptionFactory({
    required super.path,
    required this.key,
    // ignore: unused_element_parameter
    super.sqliteOptions = defaultOptions,
  });

  @override
  Future<ConnectToRecommendedResult> connectToWorker(
      WebSqlite sqlite, String name) async {
    return sqlite.connectToRecommended(
      name,
      additionalOptions: PowerSyncAdditionalOpenOptions(
        useMultipleCiphersVfs: true,
      ),
    );
  }
}

typedef PowerSyncSQLCipherOpenFactory = _WebEncryptionFactory;
