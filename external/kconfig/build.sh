#!/bin/bash

source ../init.sh http://deb.debian.org/debian/pool/main/k/kconfig-frontends/kconfig-frontends_4.11.0.1+dfsg.orig.tar.bz2 \
  5462393596a42e6efed78e1b0a56fde75466dd50452394b841f2882a78000ca8 \
  3a0a0a8e2a73f52a58864fbc212bb2d9

# Apply a hotfix patch
patch -p1 < "$INSTALL"/../hotfixes.patch &> /dev/null

# We need access to gperf, so stick it in the PATH
export PATH="$INSTALL"/../../gperf/install/bin:"$PATH"

# The usual configure-make-install
autoreconf -fis &> /dev/null
./configure --prefix="`realpath zzz`" --quiet \
  --disable-utils --disable-kconfig  > /dev/null
make --quiet > /dev/null
make --quiet install > /dev/null

# A file or two are optional, depending on the exact system.
mkdir -p zzz/share/kconfig-frontends zzz/bin
touch zzz/share/kconfig-frontends/gconf.glade
touch zzz/bin/kconfig-gconf
touch zzz/bin/kconfig-qconf

# Copy the results back home
tupify cp -r zzz/* "$INSTALL"
