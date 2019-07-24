#!/bin/bash

cd "$(realpath "$(dirname "$0")")"
if [ -z "$FORCE_BADTUP" ] && which tup &>/dev/null
then exec tup "$@"
else
  if [ ! -x external/tup/install/tup ]
  then (cd external/tup && ./build.sh)
  fi
  exec ./external/tup/install/tup "$@"
fi
