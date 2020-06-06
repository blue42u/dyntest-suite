#!/bin/bash

source ../init.sh

# GOTCHA doesn't have a release with all the bits we need. So use git for now.
git clone -q https://github.com/LLNL/GOTCHA.git gotcha

mkdir zzzbuild zzz
cmake -DCMAKE_INSTALL_PREFIX="`realpath zzz`" \
  -S gotcha -B zzzbuild > /dev/null
make -C zzzbuild --quiet > /dev/null
make -C zzzbuild --quiet install > /dev/null

tupify cp -r zzz/* "$INSTALL"
