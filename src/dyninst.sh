#!/bin/bash

# Build script for Dyninst, for use under Tup's '`run`.
# Usage: run $0 <path/to/install> [extra configure args...]
# Note: Paths should be relative, as per Tup's usual mannerisms.

SRC="`dirname "$0"`"/dyninst
BUILD="$SRC"/../../build
INS="$1"; shift

set -e  # Make sure to exit if anything funny happens

# CMake trys some things Tup doesn't like. So we use a temporary directory
# and copy the bits and bobs back after the fact.
TMP="`mktemp -d`"
trap "rm -rf $TMP" EXIT  # Make sure to clean up before exiting.

# Construct the Makefiles using CMake.
cmake -DCMAKE_INSTALL_PREFIX="`realpath $INS`" "$@" -S "$SRC" -B "$TMP" \
  > "$TMP"/cmake.log

# Ensure that CMake didn't decide to use ExternalProject
! grep -q 'external project' "$TMP"/cmake.log
rm "$TMP"/cmake.log

# Copy all the files back to "here" so that there's something to make.
cp -r "$TMP"/* .
rm -r "$TMP"
trap - EXIT

# Call our version of make to "build" everything.
"$BUILD"/make.lua "$SRC" "$INS"
