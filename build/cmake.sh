#!/bin/bash

# Build script for Dyninst, for use under Tup's '`run`.
# Usage: run $0 <path/to/src> <path/to/install> [dummy files] [extra deps] [extra CMake args]
# Note: Install path should be relative, as per Tup's usual mannerisms.

BUILD="`dirname "$0"`"
SRC="$BUILD"/../"$1"
RELSRC="$2"
INS="$3"
EXDEPS="$4"
TRANSFORMS="$5"
EXTDIR="$6"
shift 6

set -e  # Make sure to exit if anything funny happens

# CMake trys some things Tup doesn't like. So we use a temporary directory
# and copy the bits and bobs back after the fact.
TMP="`mktemp -d`"
trap "rm -rf $TMP" EXIT  # Make sure to clean up before exiting.

# Construct the Makefiles using CMake. Modify the MODULE_PATH to (try to)
# ensure ExternalProject is not used.
cmake -DCMAKE_INSTALL_PREFIX="$TMP/install-x" -DCMAKE_MODULE_PATH="$BUILD" \
  "$@" -S "$SRC" -B "$TMP" > /dev/null

# Call our version of make to "build" everything.
"$BUILD"/make.lua "$RELSRC" "$INS" "$TMP" "$EXDEPS" \
  "$TRANSFORMS $TMP/install-x=`realpath $INS`" "$EXTDIR"
