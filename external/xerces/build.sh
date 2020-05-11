#!/bin/bash

source ../init.sh \
  https://downloads.apache.org//xerces/c/3/sources/xerces-c-3.2.3.tar.xz \
  12fc99a9fc1d1a79bd0e927b8b5637a576d6656f45b0d5e70ee3694d379cc149 \
  3ec27d8e07d1486cb68740bd2806f109

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
xercesc/util/NetAccessors/Curl/CurlNetAccessor.hpp
xercesc/util/NetAccessors/Curl/CurlURLInputStream.hpp
xercesc/util/NetAccessors/BinHTTPInputStreamCommon.hpp
xercesc/util/NetAccessors/Socket/SocketNetAccessor.hpp
xercesc/util/NetAccessors/Socket/UnixHTTPURLInputStream.hpp
EOF

# Copy everything back home
tupify cp -r install/* "$INSTALL"
