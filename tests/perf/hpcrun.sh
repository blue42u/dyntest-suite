#!/bin/bash

set -e

RATE="$1"
OUT="$2"
shift 2

trap 'rm -rf "$TMP"' EXIT
TMP="`mktemp -d`"

export LD_LIBRARY_PATH=../../external/tbb/install/lib
export LD_PRELOAD="$LD_PRELOAD":../../external/tbb/install/lib/libtbbmalloc_proxy.so
./hpcrun -e REALTIME@"$RATE" -t -o "$TMP" "$@"
tar -C "$TMP" -cf "$OUT" .
