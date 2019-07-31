#!/bin/bash

set -e

TUPIFY="$LD_PRELOAD"
export LD_PRELOAD=

DST="$1"
shift 1

trap 'rm -rf "${TMPS[@]}"' EXIT
for f in "$@"; do
  TMPS+=("`mktemp -d`")
  tar -C "${TMPS[$((${#TMPS[@]}-1))]}" -xf "$f"
done

LD_PRELOAD="$TUPIFY" stat "$@" > /dev/null
LD_PRELOAD="$TUPIFY" ../../external/lua/luaexec hpcdump.lua "$DST" "${TMPS[@]}"
