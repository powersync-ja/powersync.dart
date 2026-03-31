To update the version of the PowerSync core extension used in the Dart SDK, update the following locations:

1. `powersync_core/lib/src/setup/native` (remember to update hashes as well!).
2. `POWERSYNC_CORE_VERSION` in `sqlite3_wasm_build/build.sh`.

If you've updated the core version to use a new feature, also update the minimum
version in `core_version.dart` to reflect that requirement.
