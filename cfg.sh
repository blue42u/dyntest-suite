#!/bin/bash

if [ "$#" != 1 ]; then
  echo "Usage: $0 [m|n]conf" >&2
  exit 1
fi

cd "$(realpath "$(dirname "$0")")"
./build.sh external/kconfig
LD_LIBRARY_PATH="`pwd`"/external/kconfig/install/lib:"$LD_LIBRARY_PATH" \
KCONFIG_CONFIG=tup.config \
./external/kconfig/install/bin/kconfig-"$1" tup.Kconfig
