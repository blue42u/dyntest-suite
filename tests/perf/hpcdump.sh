#!/bin/bash

set -e

DST="$1"
shift 1

trap 'rm -rf "${TMPS[@]}"' EXIT
for f in "$@"; do
  TMPS+=("`mktemp -d`")
  stat "$f" > /dev/null
  LD_PRELOAD= tar -C "${TMPS[$((${#TMPS[@]}-1))]}" -xf "$f"
done

../../external/lua/luaexec hpcdump.lua "$DST" "${TMPS[@]}"
