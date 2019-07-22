#!/bin/bash

set -e

OUT="$1"
shift 1

trap 'rm -rf "$TMP"' EXIT
TMP="`mktemp -d`"

./hpcrun -e REALTIME@100 -t -o "$TMP" "$@"
tar -C "$TMP" -cf "$OUT" .
