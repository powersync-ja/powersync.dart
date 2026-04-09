# Preparing Release

As the repository only contains a single package we expect to update frequently, the release process currently involves some manual steps.

1. Update the version in `powersync/pubspec.yaml`.
2. Run `dart tool/update_version.dart` to ensure the SDK reports its updated version in user agents.
3. Create a changelog entry for the same version.
4. Open a PR with these changes and wait for it to get merged.

## Perform Release

We create a tag for each package update named `${packageName}-v${version}`, e.g.

- `powersync-v2.0.1`
- `powersync_flutter_libs-v0.5.0+eol`

Creating and pushing those tags will trigger an automated release to pub.dev and a GitHub release containing `sqlite3.wasm` files and the web worker.
Verify the release exists and is published in [releases](https://github.com/powersync-ja/powersync.dart/releases).
