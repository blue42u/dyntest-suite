#!/bin/bash

source ../init.sh \
  http://mirror.cogentco.com/pub/apache//xerces/c/3/sources/xerces-c-3.2.2.tar.xz \
  6daca3b23364d8d883dc77a73f681242f69389e3564543287ed3d073007e0a8e \
  bb5daaa307f961aea3b9f4060d8758ba

./configure --prefix="$TMP"/install --quiet > /dev/null
make --quiet > /dev/null
make --quiet install > /dev/null

# Also install a number of headers that don't always make it
while read f; do
mkdir -p install/include/`dirname $f`
cp src/$f install/include/$f
done <<'EOF'
xercesc/util/MutexManagers/PosixMutexMgr.hpp
xercesc/util/MutexManagers/WindowsMutexMgr.hpp
xercesc/util/MutexManagers/NoThreadMutexMgr.hpp
xercesc/util/MutexManagers/StdMutexMgr.hpp
xercesc/util/Transcoders/ICU/ICUTransService.hpp
xercesc/util/Transcoders/MacOSUnicodeConverter/MacOSUnicodeConverter.hpp
xercesc/util/Transcoders/Iconv/IconvTransService.hpp
xercesc/util/Transcoders/Win32/Win32TransService.hpp
xercesc/util/Transcoders/IconvGNU/IconvGNUTransService.hpp
EOF

# Copy everything back home
tupify cp -r install/* "$INSTALL"
