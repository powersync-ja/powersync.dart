//
//  Generated file. Do not edit.
//

// clang-format off

#include "generated_plugin_registrant.h"

#include <powersync_flutter_libs/powersync_flutter_libs_plugin.h>
#include <sqlcipher_flutter_libs/sqlite3_flutter_libs_plugin.h>

void fl_register_plugins(FlPluginRegistry* registry) {
  g_autoptr(FlPluginRegistrar) powersync_flutter_libs_registrar =
      fl_plugin_registry_get_registrar_for_plugin(registry, "PowersyncFlutterLibsPlugin");
  powersync_flutter_libs_plugin_register_with_registrar(powersync_flutter_libs_registrar);
  g_autoptr(FlPluginRegistrar) sqlcipher_flutter_libs_registrar =
      fl_plugin_registry_get_registrar_for_plugin(registry, "Sqlite3FlutterLibsPlugin");
  sqlite3_flutter_libs_plugin_register_with_registrar(sqlcipher_flutter_libs_registrar);
}
