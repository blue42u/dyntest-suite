#!/bin/bash

set -e

trap 'rm -rf "$TMPA" "$TMPB"' EXIT
TMPA="`mktemp -d`"
TMPB="`mktemp -d`"

tar xf "$1" --one-top-level="$TMPA"
rmdir "$TMPB"
../../reference/hpctoolkit/install/libexec/hpctoolkit/hpcprof-bin \
  -o "$TMPB" "$TMPA"
tar -C "$TMPB" -cf "$2" .
