#!/bin/bash

# A little installation script that handles symlinks properly
# and that Tup won't complain about quite as much.

PATCHELF="`dirname $0`"/../external/patchelf/install/bin/patchelf

set -e

case "`stat -c%F "$1"`" in
"regular file")
  cp -d "$1" "$2"
  if [ -z "$3" ]; then exit 0; fi
  if readelf -d "$2" | grep -q 'There is no dynamic section'; then exit 0; fi
  "$PATCHELF" --set-rpath "$("$PATCHELF" --print-rpath "$2"):$3" "$2"
  ;;
"symbolic link")
  touch "$2"
  LD_PRELOAD= ln -sf "`stat -c%N "$1" | sed "s/.*-> '\(.*\)'.*/\1/"`" "$2"
  ;;
*) echo "Can't install file of type '`stat -c%F "$1"`'!"; exit 1
esac
