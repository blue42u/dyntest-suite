#!/bin/bash

source ../init.sh https://github.com/oneapi-src/oneTBB/archive/2020_U1.tar.gz \
  d80ca22c224ab7ef913dfae72c23fc1434b6aa46bfd472916d8c874c90881f5e \
  1e9c8914683d31d1721ee68d9f1aab5d

# TBB has a very weird build system. We do our best to get around it.
make -srf build/Makefile.tbb tbb_root="$TMP" cfg=release
make -srf build/Makefile.tbbmalloc tbb_root="$TMP" cfg=release malloc
make -srf build/Makefile.tbbproxy tbb_root="$TMP" cfg=release tbbproxy
make -srf build/Makefile.tbb tbb_root="$TMP" cfg=preview tbb_cpf=1

# Copy out the built .so's first
tupify cp "$TMP"/libtbb.so.2 "$INSTALL"/lib/libtbb.so.2
tupify cp "$TMP"/libtbbmalloc.so.2 "$INSTALL"/lib/libtbbmalloc.so.2
tupify cp "$TMP"/libtbbmalloc_proxy.so.2 "$INSTALL"/lib/libtbbmalloc_proxy.so.2
tupify cp "$TMP"/libtbb_preview.so.2 "$INSTALL"/lib/libtbb_preview.so.2

# Stitch in the RUNPATH. Makes preloading easier.
RP="`realpath "$INSTALL"/lib`"
PE="$INSTALL"/../../patchelf/install/bin/patchelf
rpath() { tupify "$PE" --set-rpath "$RP:$("$PE" --print-rpath "$1")" "$1"; }
rpath "$INSTALL"/lib/libtbb.so.2
rpath "$INSTALL"/lib/libtbbmalloc.so.2
rpath "$INSTALL"/lib/libtbbmalloc_proxy.so.2
rpath "$INSTALL"/lib/libtbb_preview.so.2

# Copy out the headers next
tupify cp -r "$TMP"/include/tbb "$INSTALL"/include

# Add the usual simplified symlinks to make things clean
tupify ln -s libtbb.so.2 "$INSTALL"/lib/libtbb.so
tupify ln -s libtbbmalloc.so.2 "$INSTALL"/lib/libtbbmalloc.so
tupify ln -s libtbbmalloc_proxy.so.2 "$INSTALL"/lib/libtbbmalloc_proxy.so
tupify ln -s libtbb_preview.so.2 "$INSTALL"/lib/libtbb_preview.so
