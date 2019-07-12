#!/bin/bash

source ../init.sh https://tukaani.org/xz/xz-5.2.4.tar.xz \
  9717ae363760dedf573dad241420c5fea86256b65bc21d2cf71b2b12f0544f4b \
  003e4d0b1b1899fc6e3000b24feddf7c

./configure --prefix="`realpath zzz`" --quiet > /dev/null
make --quiet > /dev/null
make --quiet install > /dev/null

tupify cp -r zzz/* "$INSTALL"
