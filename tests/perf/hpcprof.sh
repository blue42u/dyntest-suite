#!/bin/bash

set -e

SRC="$1"
DST="$2"
shift 2

trap 'rm -rf "$TMPA" "$TMPB"' EXIT
TMPA="`mktemp -d`"
TMPB="`mktemp -d`"

# Degraded Tup doesn't like us writing to a tmpdir, and getting the
# exclusions straight doesn't always work. So we do this instead.
stat "$SRC" > /dev/null
LD_PRELOAD= tar -C "$TMPA" -xf "$SRC"

rmdir "$TMPB"
../../reference/hpctoolkit/install/bin/hpcprof.real \
 "$@" -o "$TMPB" "$TMPA"
tar -C "$TMPB" -cf "$DST" .
