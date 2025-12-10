To update the version of the PowerSync core extension used in the Dart SDK, update the following locations:

1. `scripts/download_core_binary_demos.dart` and `scripts/init_powersync_core_binary.dart`.
2. `build.gradle` for `powersync_flutter_libs`.
3. `powersync_flutter_libs` (iOS and macOS) for `powersync_flutter_libs`.
4. `POWERSYNC_CORE_VERSION` in `sqlite3_wasm_build/build.sh`.
5. `exact` in `packages/powersync_flutter_libs/darwin/powersync_flutter_libs/Package.swift`

After updating, run `podfile:update` to update the podfile locks for demo projects.
If you've updated the core version to use a new feature, also update the minimum
version in `core_version.dart` to reflect that requirement.
