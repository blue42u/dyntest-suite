#!/bin/bash

source ../init.sh https://www.prevanders.net/libdwarf-20200114.tar.gz \
  cffd8d600ca3181a5194324c38d50f94deb197249b2dea92d18969a7eadd2c34 \
  fa710b5e4662330cbbf55a565e5c497b

# The usual configure-make-install
./configure --prefix="`realpath zzz`" --quiet --enable-shared > /dev/null
make --quiet > /dev/null
make --quiet install > /dev/null

# Copy the outputs back home
tupify cp -r zzz/* "$INSTALL"
