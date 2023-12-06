import 'package:sqlite_async/sqlite3_common.dart';
import '../open_factory_interface.dart' as open_factory;

class PowerSyncOpenFactory extends open_factory.PowerSyncOpenFactory {
  PowerSyncOpenFactory({required super.path});

  void enableExtension() {
    // No op for web
  }

  void setupFunctions(CommonDatabase db) {
    // No op for web
  }
}
