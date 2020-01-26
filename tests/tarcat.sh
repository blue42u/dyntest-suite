#!/bin/bash

set -e
DST="`realpath $1`"
shift 1

trap 'rm -rf "$TMP"' EXIT
TMP="`mktemp -d`"

for f in "$@"; do
  if [ "`(LD_PRELOAD= tar -taf "$f" | echo -n) 2>&1`" ]; then
    cp "$f" "$TMP"
  else
    OUT="`basename "${f%.*}" .tar`"
    mkdir -p "$TMP"/"$OUT"
    stat "$f" > /dev/null
    LD_PRELOAD= tar -C "$TMP"/"$OUT" -xaf "$f"
  fi
done

cd "$TMP"
tar cf out.tar *
xz -cv out.tar > "$DST"
