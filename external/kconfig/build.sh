#!/bin/bash

source ../init.sh

# The released version has an old configure and so kinda breaks a bit.
# We need autotools and libtool anyway, so just use the git.
git clone git://ymorin.is-a-geek.org/kconfig-frontends kconfig
cd kconfig
autoreconf -fis &> /dev/null

# The usual configure-make-install
./configure --prefix="`realpath zzz`" --quiet \
  --disable-utils --disable-kconfig > /dev/null
make --quiet > /dev/null
make --quiet install > /dev/null

# Copy the results back home
tupify cp -r zzz/* "$INSTALL"
