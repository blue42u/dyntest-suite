#!/bin/bash

set -e
DST="`realpath $1`"
shift 1

trap 'rm -rf "$TMP"' EXIT
TMP="`mktemp -d`"

for f in "$@"; do
  case "$f" in
  *.tar)
    mkdir -p "$TMP"/"`basename "$f" .tar`"
    stat "$f" > /dev/null
    LD_PRELOAD= tar -C "$TMP"/"`basename "$f" .tar`" -xf "$f"
    ;;
  *) cp "$f" "$TMP"
  esac
done

cd "$TMP"
tar cf out.tar *
xz -cv out.tar > "$DST"
