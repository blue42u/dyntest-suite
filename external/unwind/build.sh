#!/bin/bash

source ../init.sh \
  http://download.savannah.nongnu.org/releases/libunwind/libunwind-1.3.1.tar.gz\
  43997a3939b6ccdf2f669b50fdb8a4d3205374728c2923ddc2354c65260214f8 \
  a04f69d66d8e16f8bf3ab72a69112cd6

./configure --prefix="`realpath zzz`" --quiet > /dev/null
make --quiet > /dev/null
make --quiet install > /dev/null

tupify cp -r zzz/* "$INSTALL"
