#!/bin/bash

set -e

usage() {
  echo "Usage: $0 [-{m|n|c|g|q}]" >&2
  exit 1
}

if [ "$#" -gt 1 ]; then usage; fi

CONF=nconf
if [ "$#" = 1 ]; then
  if [ "${1#-}" = "$1" ]; then usage; fi
  CONF="${1##-}"conf
fi

cd "$(realpath "$(dirname "$0")")"
./build.sh external/kconfig
LD_LIBRARY_PATH="`pwd`"/external/kconfig/install/lib:"$LD_LIBRARY_PATH" \
KCONFIG_CONFIG=tup.config \
./external/kconfig/install/bin/kconfig-"$CONF" tup.Kconfig
