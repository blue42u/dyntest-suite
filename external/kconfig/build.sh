#!/bin/bash

source ../init.sh

# The released version has an old configure and so kinda breaks a bit.
# We need autotools and libtool anyway, so just use the git.
git clone git://ymorin.is-a-geek.org/kconfig-frontends kconfig
cd kconfig
autoreconf -fis &> /dev/null

# The usual configure-make-install
./configure --prefix="`realpath zzz`" --quiet \
  --disable-utils --disable-kconfig  > /dev/null
make --quiet > /dev/null
make --quiet install > /dev/null

# A file or two are optional, depending on the exact system.
touch zzz/share/kconfig-frontends/gconf.glade
touch zzz/bin/kconfig-gconf
touch zzz/bin/kconfig-qconf

# Copy the results back home
tupify cp -r zzz/* "$INSTALL"
