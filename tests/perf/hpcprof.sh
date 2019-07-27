#!/bin/bash

set -e

TUPIFY="$LD_PRELOAD"
export LD_PRELOAD=

SRC="$1"
DST="$2"
shift 2

trap 'rm -rf "$TMPA" "$TMPB"' EXIT
TMPA="`mktemp -d`"
TMPB="`mktemp -d`"

LD_PRELOAD="$TUPIFY" stat "$SRC" > /dev/null
tar -C "$TMPA" -xf "$SRC"
rmdir "$TMPB"
../../reference/hpctoolkit/install/libexec/hpctoolkit/hpcprof-bin \
 "$@" -o "$TMPB" "$TMPA"
LD_PRELOAD="$TUPIFY" tar -C "$TMPB" -cf "$DST" .
