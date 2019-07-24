#!/bin/bash

set -e

TUPIFY="$LD_PRELOAD"
export LD_PRELOAD=

trap 'rm -rf "$TMPA" "$TMPB"' EXIT
TMPA="`mktemp -d`"
TMPB="`mktemp -d`"

LD_PRELOAD="$TUPIFY" stat "$1" > /dev/null
tar -C "$TMPA" -xf "$1"
rmdir "$TMPB"
../../reference/hpctoolkit/install/libexec/hpctoolkit/hpcprof-bin \
  -o "$TMPB" "$TMPA"
LD_PRELOAD="$TUPIFY" tar -C "$TMPB" -cf "$2" .
