#!/bin/bash

source ../init.sh https://ftp.gnu.org/pub/gnu/gperf/gperf-3.1.tar.gz \
  588546b945bba4b70b6a3a616e80b4ab466e3f33024a352fc2198112cdbb3ae2 \
  9e251c0a618ad0824b51117d5d9db87e

# The usual configure-make-install
./configure --prefix="`realpath zzz`" --quiet > /dev/null
make --quiet > /dev/null
make --quiet install > /dev/null

# Copy the results back home
tupify cp -r zzz/* "$INSTALL"
