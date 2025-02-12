This directory includes tools to build `sqlite3.wasm` files compatible with the
PowerSync Dart SDK.

This build process is adapted from [`package:sqlite3`][upstream], with patches
applied to link the [PowerSync SQLite extension][core] statically.

### Working on patches

To adapt the patches from an `$old` version to a `$new` version:

1. Clone `https://github.com/simolus3/sqlite3.dart.git` somewhere.
2. Create a branch tracking the old version: `git switch -c powersync-patches sqlite3-$old`.
3. Apply the existing patches: `git am patches/*`.
4. Rebase onto a new upstream release if necessary: `git rebase --onto sqlite3-$new sqlite3-$old powersync-patches`
5. Obtain a new patchset with `git format-patch sqlite3-$new..HEAD`.

[upstream]: https://github.com/simolus3/sqlite3.dart/tree/main/sqlite3/assets/wasm
[core]: https://github.com/powersync-ja/powersync-sqlite-core
