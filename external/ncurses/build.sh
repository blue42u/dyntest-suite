#!/bin/bash

source ../init.sh ftp://ftp.invisible-island.net/ncurses/ncurses-6.1.tar.gz \
  aa057eeeb4a14d470101eff4597d5833dcef5965331be3528c08d99cebaa0d17 \
  98c889aaf8d23910d2b92d65be2e737a

# The usual configure-make-install
./configure --prefix="`realpath zzz`" --quiet \
  --with-terminfo-dirs="$INSTALL"/share/terminfo \
  --without-progs --without-manpages --with-shared &> /dev/null
make --quiet &> /dev/null
make --quiet install &> /dev/null

# Copy the results back home
tupify cp -r zzz/* "$INSTALL"
