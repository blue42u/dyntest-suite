#!/bin/bash

source ../init.sh

# Libmonitor comes from a git repo, clone it here
git clone https://github.com/hpctoolkit/libmonitor.git monitor
cd monitor

# After that, automake
./configure --prefix="`realpath zzz`" --quiet > /dev/null
make --quiet > /dev/null
make --quiet install > /dev/null

# Copy back home
tupify cp -r zzz/* "$INSTALL"
