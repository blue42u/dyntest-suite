#!/bin/bash

export CPPFLAGS="-g -include `pwd`/valc++.h"
VER="`gcc --version | head -n1 | awk 'NF>1{print $NF}'`"
if [ "$VER" != 8.3.0 ]; then
  echo "ERROR: This script is set up for GCC 8.3.0, please use that!" >&2
  exit 1
fi

CORES=`grep -c '^processor' /proc/cpuinfo`
source ../init.sh \
  ftp://ftp.mirrorservice.org/sites/sourceware.org/pub/gcc/releases/gcc-$VER/gcc-$VER.tar.xz \
  64baadfe6cc0f4947a84cb12d7f0dfaf45bb58b7e92461639596c21e02d97d2c \
  65b210b4bfe7e060051f799e0f994896

# The usual configure-make-install
./configure --prefix="`realpath zzz`" \
  --disable-libquadmath --disable-bootstrap \
  --disable-linux-futex --disable-mudflap --disable-nls \
  --enable-languages=c,c++ --enable-threads=posix --enable-tls \
  --with-gmp=/usr --with-mpfr=/usr --with-mpc=/usr \
  --quiet > /dev/null
make --quiet -j$CORES > /dev/null
make --quiet install > /dev/null

# Unify bits and bobs
for d in lib32 lib64; do
  if test -d zzz/$d; then
    mv zzz/$d/* zzz/lib
    rmdir zzz/$d
  fi
done

# Remove stuff that we don't actually need
rm -rf zzz/share zzz/include zzz/bin zzz/libexec zzz/lib/gcc

# Copy the results back home
tupify cp -r zzz/* "$INSTALL"
