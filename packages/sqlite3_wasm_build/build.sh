#!/bin/sh
set -e

SQLITE_VERSION="3.2.0"
POWERSYNC_CORE_VERSION="0.4.13"
SQLITE_PATH="sqlite3.dart"

if [ -d "$SQLITE_PATH" ]; then
  echo "Deleting existing clone"
  rm -rf $SQLITE_PATH
fi

git clone --branch "sqlite3-$SQLITE_VERSION" --depth 1 https://github.com/simolus3/sqlite3.dart.git $SQLITE_PATH

cd $SQLITE_PATH
git apply ../patches/*

cd "sqlite3_wasm_build/"

cmake -Dwasi_sysroot=/opt/homebrew/share/wasi-sysroot \
    -Dclang=/opt/homebrew/opt/llvm/bin/clang\
    -DPOWERSYNC_VERSION="$POWERSYNC_CORE_VERSION" \
    -S src -B .dart_tool/sqlite3_build
cmake --build .dart_tool/sqlite3_build/ -t output -j

cd ../../
mkdir -p dist
cp $SQLITE_PATH/sqlite3_wasm_build/out/*.wasm dist
