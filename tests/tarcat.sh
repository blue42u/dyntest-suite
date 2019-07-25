#!/bin/bash

set -e
DST="`realpath $1`"
shift 1

trap 'rm -rf "$TMP"' EXIT
TMP="`mktemp -d`"

TUPIFY="$LD_PRELOAD"
export LD_PRELOAD=

for f in "$@"; do
  case "$f" in
  *.tar)
    mkdir -p "$TMP"/"`basename "$f" .tar`"
    tar -C "$TMP"/"`basename "$f" .tar`" -xf "$f"
    ;;
  *) cp "$f" "$TMP"
  esac
done

cd "$TMP"
LD_PRELOAD="$TUPIFY" tar -cJf "$DST" *