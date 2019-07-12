#!/bin/bash

source ../init.sh https://www.zlib.net/zlib-1.2.11.tar.xz \
  4ff941449631ace0d4d203e3483be9dbc9da454084111f97ea0a2114e19bf066 \
  85adef240c5f370b308da8c938951a68

./configure --prefix="$TMP"/install >/dev/null
make --quiet > /dev/null
make --quiet install > /dev/null

tupify cp -r install/* "$INSTALL"
