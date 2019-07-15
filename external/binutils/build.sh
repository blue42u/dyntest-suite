#!/bin/bash

source ../init.sh https://ftpmirror.gnu.org/binutils/binutils-2.32.tar.xz \
  0ab6c55dd86a92ed561972ba15b9b70a8b9f75557f896446c82e8b36e473ee04 \
  0d174cdaf85721c5723bf52355be41e6

export CPPFLAGS='-g'

# The usual configure-make-install
./configure --prefix="`realpath zzz`" --quiet \
  --enable-lto --enable-install-libiberty > /dev/null
make --quiet > /dev/null
make --quiet install > /dev/null

# Do some cleanup on the install directory, and don't use lib64.
rm -f zzz/share/info/dir
if test -d zzz/lib64; then
  mv zzz/lib64/* zzz/lib
  rmdir zzz/lib64
fi

# Copy the results back home
tupify cp -r zzz/* "$INSTALL"
