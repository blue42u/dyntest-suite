#!/bin/bash

# Build script for Elfutils, for use under Tup's '`run`.
# Usage: run $0 <path/to/src> <path/to/install> [extra deps] [extra configure args...]
# Note: Paths should be relative, as per Tup's usual mannerisms.

BUILD="`dirname "$0"`"
SRC="$BUILD"/../"$1"
RELSRC="$2"
INS="$3"
EXDEPS="$4"
TRANSFORMS="$5"
EXDIR="$6"
shift 6

set -e  # Make sure to exit if anything funny happens

# Install automake in the source dir. Make sure the cache is never created.
export AUTOM4TE="$BUILD"/autom4te-no-cache
if [ ! -x "$SRC"/configure ]; then
autoreconf -is "$SRC" >&2 2> /dev/null
fi

# HPCToolkit likes to use git. Tup doesn't, so this handles that little issue.
export REAL_LDD="`which ldd`"
export PATH="`realpath $BUILD`"/bin:"$PATH"

# Configure trys some things that Tup really doesn't like. So we configure in a
# temporary directory and copy the important parts back to "here".
HERE="`pwd`"
RSRC="`realpath "$SRC"`"
RINS="`realpath "$INS"`"
TMP="`mktemp -d`"
trap "rm -rf $TMP; cd '$SRC' && git clean -fxd" EXIT  # Make sure to clean up before exiting.
cd "$TMP"

# Construct the makefiles that will make up everything.
"$RSRC"/configure --disable-dependency-tracking --prefix="$RINS" "$@" >/dev/null

# Head back to "here"
cd "$HERE"

# Call our version of make to "build" everything.
"$BUILD"/make.lua "$RELSRC" "$INS" "$TMP" "$EXDEPS" "$TRANSFORMS" "$EXDIR"
