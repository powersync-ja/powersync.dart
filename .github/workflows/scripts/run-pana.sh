#!/bin/bash
set -e

# Get the root directory of your project
ROOT_DIR=$(pwd)

# Specify the path to the packages folder
PACKAGES_DIR="$ROOT_DIR/packages"

# Iterate over each package folder
for PACKAGE in "$PACKAGES_DIR"/*; do
  # Check if it's a directory
  if [ -d "$PACKAGE" ]; then
    echo "Analyzing package in: $PACKAGE"

    # Change into the package directory
    cd "$PACKAGE" || exit

    # Run the pana command
    flutter pub global run pana --no-warning --exit-code-threshold 10

    # Return to the root directory
    cd "$ROOT_DIR" || exit
  fi
done
