#!/bin/bash

source ../init.sh \
  https://nixos.org/releases/patchelf/patchelf-0.10/patchelf-0.10.tar.bz2 \
  f670cd462ac7161588c28f45349bc20fb9bd842805e3f71387a320e7a9ddfcf3 \
  6c3f3a06a95705870d129494a6880106

# The usual configure-make-install
./configure --prefix="`realpath zzz`" --quiet > /dev/null
make --quiet > /dev/null
make --quiet install > /dev/null

# Copy the results back home
tupify cp -r zzz/* "$INSTALL"
