To update the version of the PowerSync core extension used in the Dart SDK, update the following locations:

1. `scripts/download_core_binary_demos.dart` and `scripts/init_powersync_core_binary.dart`.
2. `build.gradle` for `powersync_flutter_libs`.
3. `powersync_flutter_libs` (iOS and macOS) for `powersync_flutter_libs`.
4. `POWERSYNC_CORE_VERSION` in `sqlite3_wasm_build/build.sh`.

After updating, run `podfile:update` to update the podfile locks for demo projects.
