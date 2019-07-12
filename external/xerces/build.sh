#!/bin/sh

INSTALL="`pwd`"
set -e

# Hide from Tup for a bit, we know what we're doing
REAL_LD_PRELOAD="$LD_PRELOAD"
export LD_PRELOAD=

# Make a temporary directory where we'll stick stuff
TMP="`realpath zzztmp`"
trap "rm -rf $TMP" EXIT
rm -rf zzztmp
mkdir zzztmp
cd "$TMP"

echo "Downloading Xerces..."
URL=http://mirror.cogentco.com/pub/apache//xerces/c/3/sources/xerces-c-3.2.2.tar.xz
if which curl > /dev/null; then
  curl -Lso xerces.tar.xz $URL
elif which wget > /dev/null; then
  wget -O xerces.tar.xz $URL
else
  echo "No download program available, abort!" >&2
  exit 1
fi

if which shasum > /dev/null; then
echo "Checking SHAsum..."
shasum -qca 256 - <<'EOF'
6daca3b23364d8d883dc77a73f681242f69389e3564543287ed3d073007e0a8e  xerces.tar.xz
EOF
else
echo "Checking MD5sum..."
md5sum -c --quiet - <<'EOF'
bb5daaa307f961aea3b9f4060d8758ba  xerces.tar.xz
EOF
fi

echo "Uncompressing tarball..."
tar xJf xerces.tar.xz --strip-components=1

echo "Configuring..."
./configure --prefix="$TMP"/install \
  > /dev/null

echo "Building..."
make > /dev/null

echo "Installing..."
make install > /dev/null

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

echo "Copying results..."
export LD_PRELOAD="$REAL_LD_PRELOAD"
cd "$INSTALL"
cp -r "$TMP"/install/* .
