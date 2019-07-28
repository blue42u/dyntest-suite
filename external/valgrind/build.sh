#!/bin/bash

source ../init.sh https://sourceware.org/pub/valgrind/valgrind-3.15.0.tar.bz2 \
  417c7a9da8f60dd05698b3a7bc6002e4ef996f14c13f0ff96679a16873e78ab1 \
  46e5fbdcbc3502a5976a317a0860a975

# The usual configure-make-install
./configure --prefix="`realpath zzz`" --quiet --disable-dependency-tracking \
  --enable-lto --enable-only64bit --with-mpicc=false > /dev/null
make --quiet > /dev/null
make --quiet install > /dev/null

# Copy the results back home
tupify cp -r zzz/* "$INSTALL"
