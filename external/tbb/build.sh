#!/bin/bash

source ../init.sh https://github.com/intel/tbb/archive/2019_U8.tar.gz \
  7b1fd8caea14be72ae4175896510bf99c809cd7031306a1917565e6de7382fba \
  7c371d0f62726154d2c568a85697a0ad

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
tupify "$PE" --set-rpath "$RP" "$INSTALL"/lib/libtbb.so.2
tupify "$PE" --set-rpath "$RP" "$INSTALL"/lib/libtbbmalloc.so.2
tupify "$PE" --set-rpath "$RP" "$INSTALL"/lib/libtbbmalloc_proxy.so.2
tupify "$PE" --set-rpath "$RP" "$INSTALL"/lib/libtbb_preview.so.2

# Copy out the headers next
tupify cp -r "$TMP"/include/tbb "$INSTALL"/include

# Add the usual simplified symlinks to make things clean
tupify ln -s libtbb.so.2 "$INSTALL"/lib/libtbb.so
tupify ln -s libtbbmalloc.so.2 "$INSTALL"/lib/libtbbmalloc.so
tupify ln -s libtbbmalloc_proxy.so.2 "$INSTALL"/lib/libtbbmalloc_proxy.so
tupify ln -s libtbb_preview.so.2 "$INSTALL"/lib/libtbb_preview.so
