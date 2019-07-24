#!/bin/bash

source ../init.sh https://downloads.sourceforge.net/project/bzip2/bzip2-1.0.6.tar.gz \
  a2848f34fcd5d6cf47def00461fcb528a0484d8edef8208d6d2e2909dc61d9cd \
  00b516f4704d4a7cb50a1d97e6e8e15b

# Makefile designed for UNIX systems. I only really support 'nix too.
make --quiet > /dev/null
make --quiet install PREFIX="`realpath zzz`" > /dev/null

# BZip's has an extra one for the shared side
make --quiet clean > /dev/null
make --quiet -f Makefile-libbz2_so > /dev/null
ln -sf libbz2.so.1.0 libbz2.so

# Copy the results back home
tupify cp -r zzz/* "$INSTALL"
tupify cp -d *.so* "$INSTALL"/lib
