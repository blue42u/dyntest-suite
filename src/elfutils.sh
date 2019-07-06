#!/bin/bash

# Build script for Elfutils, for use under Tup's '`run`.
# Usage: run $0 <path/to/install> [extra configure args...]
# Note: Paths should be relative, as per Tup's usual mannerisms.

SRC="`dirname "$0"`"/elfutils
BUILD="$SRC"/../../build
INS="$1"; shift

set -e  # Make sure to exit if anything funny happens

# Install automake in the source dir. Make sure the cache is never created.
export AUTOM4TE="$BUILD"/autom4te-no-cache
autoreconf -is "$SRC" >&2 2> /dev/null

# Configure trys some things that Tup really doesn't like. So we configure in a
# temporary directory and copy the important parts back to "here".
HERE="`pwd`"
RSRC="`realpath "$SRC"`"
RINS="`realpath "$INS"`"
TMP="`mktemp -d`"
trap "rm -rf $TMP" EXIT  # Make sure to clean up before exiting.
cd "$TMP"

# Construct the makefiles that will make up everything.
"$RSRC"/configure --enable-maintainer-mode --disable-dependency-tracking \
  --prefix="$RINS" "$@" > /dev/null

# Copy all the files back to "here" so that there's something to make.
cp -r * "$HERE"/
rm -r "$TMP"
cd "$HERE"
trap - EXIT

# Call our version of make to "build" everything.
"$BUILD"/make.lua "$SRC" "$INS"
